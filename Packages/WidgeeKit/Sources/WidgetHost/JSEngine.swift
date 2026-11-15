import Foundation
import JavaScriptCore
import ObjectiveC

typealias ExecutionLimitCallback = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
private typealias SetLimitFn = @convention(c) (JSContextGroupRef, Double, ExecutionLimitCallback?, UnsafeMutableRawPointer?) -> Void
private typealias ClearLimitFn = @convention(c) (JSContextGroupRef) -> Void

/// Приватный API JavaScriptCore (JSContextRefPrivate.h), берётся через dlsym.
private let setLimitFn: SetLimitFn? = {
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else { return nil }
    return unsafeBitCast(p, to: SetLimitFn.self)
}()
private let clearLimitFn: ClearLimitFn? = {
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupClearExecutionTimeLimit") else { return nil }
    return unsafeBitCast(p, to: ClearLimitFn.self)
}()

enum JSEngineError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let m) = self { m } else { "" } }
}

/// Один изолированный JSContext в собственной JSContextGroup и на собственной очереди.
/// Все JS-объекты трогаются только на `queue`.
final class JSEngine: NSObject, @unchecked Sendable {
    let queue: DispatchQueue
    private let root: URL
    private let group: JSContextGroupRef
    private let context: JSContext
    private let logger: @Sendable (String, String) -> Void
    private var loadError: String?
    private var lastException: String?

    /// JSC сам отклоняет «голые» спецификаторы ("Module specifier: widgee does not start with /, ./ or ../")
    /// ещё до вызова делегата, поэтому хост переписывает `"widgee"` в этот абсолютный виртуальный путь.
    static let sdkSpecifier = "/__widgee__/sdk.js"
    static let entryName = ".widgee-entry.js"
    static let widgetFile = "widget.js"

    init(root: URL, logger: @escaping @Sendable (String, String) -> Void) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.logger = logger
        self.queue = DispatchQueue(label: "widgee.js.\(UUID().uuidString)", qos: .userInitiated)
        self.group = JSContextGroupCreate()
        let g = JSGlobalContextCreateInGroup(group, nil)!
        self.context = JSContext(jsGlobalContextRef: g)
        JSGlobalContextRelease(g)
        super.init()
        context.setValue(self, forKey: "moduleLoaderDelegate")
        context.exceptionHandler = { [weak self] _, ex in
            self?.lastException = ex?.toString() ?? "unknown exception"
        }
        installConsole()
    }

    deinit { JSContextGroupRelease(group) }

    private func installConsole() {
        for (name, level) in [("log", "log"), ("info", "log"), ("warn", "log"), ("error", "error")] {
            let fn: @convention(block) () -> Void = { [logger] in
                let args = JSContext.currentArguments() as? [JSValue] ?? []
                logger(level, args.map { $0.toString() ?? "" }.joined(separator: " "))
            }
            let console = context.objectForKeyedSubscript("console")?.isObject == true
                ? context.objectForKeyedSubscript("console")!
                : { let o = JSValue(newObjectIn: context)!; context.setObject(o, forKeyedSubscript: "console" as NSString); return o }()
            console.setObject(unsafeBitCast(fn, to: AnyObject.self), forKeyedSubscript: name as NSString)
        }
    }

    // MARK: time limit

    /// Ограничивает выполнение скриптов группы; по истечении JSC прерывает JS (исключение «terminated»).
    func withTimeLimit<T>(_ seconds: Double, _ body: () -> T) -> T {
        guard let setLimitFn, let clearLimitFn else { return body() }
        setLimitFn(group, seconds, { _, _ in true }, nil)
        defer { clearLimitFn(group) }
        return body()
    }

    static var timeLimitAvailable: Bool { setLimitFn != nil && clearLimitFn != nil }

    // MARK: loading (вызывать на queue)

    func loadWidget(timeout: Double) throws {
        let entry = root.appendingPathComponent(Self.entryName)
        let src = """
        import def from "./\(Self.widgetFile)";
        if (def === null || typeof def !== "object" || typeof def.render !== "function") {
          throw new TypeError("widget.js must default-export defineWidget({ render })");
        }
        globalThis.__widgeeSources = (settingsJSON) => {
          const src = typeof def.sources === "function" ? def.sources(JSON.parse(settingsJSON)) : def.sources;
          return JSON.stringify(src ?? {});
        };
        globalThis.__widgeeInvoke = (json) => JSON.stringify(def.render(JSON.parse(json)));
        """
        loadError = nil; lastException = nil; entrySource = src
        let script: AnyObject
        do { script = try makeModuleScript(src, entry) }
        catch { throw JSEngineError.message("failed to parse module: \(error)") }

        let result = withTimeLimit(timeout) {
            context.perform(NSSelectorFromString("evaluateJSScript:"), with: script)?.takeUnretainedValue() as? JSValue
        }
        // Загрузка резолвится синхронно; промис результата отражает ошибки evaluate.
        var rejection: String?
        if let p = result, p.isObject, p.hasProperty("then") {
            let onReject: @convention(block) (JSValue) -> Void = { rejection = $0.toString() }
            let noop: @convention(block) (JSValue) -> Void = { _ in }
            p.invokeMethod("then", withArguments: [unsafeBitCast(noop, to: AnyObject.self),
                                                    unsafeBitCast(onReject, to: AnyObject.self)])
        }
        if let e = loadError ?? lastException ?? rejection { throw JSEngineError.message(clean(e)) }
        guard context.objectForKeyedSubscript("__widgeeInvoke")?.isObject == true else {
            throw JSEngineError.message("the module did not finish loading")
        }
    }

    /// JSScript (+scriptOfType:withSource:andSourceURL:andBytecodeCache:inVirtualMachine:error:) не входит
    /// в публичные заголовки SDK, поэтому вызывается через Obj-C runtime. JSScriptType module = 1.
    private func makeModuleScript(_ source: String, _ url: URL) throws -> AnyObject {
        guard let cls = NSClassFromString("JSScript") else {
            throw JSEngineError.message("JSScript is unavailable in this version of JavaScriptCore")
        }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt, NSString, NSURL, AnyObject?, AnyObject,
                                       UnsafeMutablePointer<AnyObject?>) -> AnyObject?
        let sel = NSSelectorFromString("scriptOfType:withSource:andSourceURL:andBytecodeCache:inVirtualMachine:error:")
        guard let m = class_getClassMethod(cls, sel) else {
            throw JSEngineError.message("JSScript: script factory selector not found")
        }
        let fn = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        var err: AnyObject?
        guard let s = fn(cls, sel, 1, source as NSString, url as NSURL, nil, context.virtualMachine, &err) else {
            throw JSEngineError.message((err as? NSError)?.localizedDescription ?? "failed to create JSScript")
        }
        return s
    }

    private func clean(_ s: String) -> String { s }

    /// JSON объявленных источников (`def.sources`; если это функция, она вызывается с `settings`).
    func readSources(settingsJSON: String, timeout: Double) throws -> String {
        lastException = nil
        guard let fn = context.objectForKeyedSubscript("__widgeeSources"), fn.isObject else {
            throw JSEngineError.message("sources: reader function is unavailable")
        }
        let r = withTimeLimit(timeout) { fn.call(withArguments: [settingsJSON]) }
        if let e = lastException {
            context.exception = nil
            if e.contains("terminated") { throw JSEngineError.message("sources timed out") }
            throw JSEngineError.message("sources: exception: \(e)")
        }
        guard let s = r, s.isString, let str = s.toString() else {
            throw JSEngineError.message("sources: could not read the result")
        }
        return str
    }

    /// Вызов render. Возвращает JSON-строку дерева.
    func invokeRender(json: String, timeout: Double) throws -> String {
        lastException = nil
        let fn = context.objectForKeyedSubscript("__widgeeInvoke")!
        let r = withTimeLimit(timeout) { fn.call(withArguments: [json]) }
        if let e = lastException {
            context.exception = nil
            if e.contains("terminated") { throw JSEngineError.message("render timed out") }
            throw JSEngineError.message("exception in render: \(e)")
        }
        guard let s = r, s.isString, let str = s.toString() else {
            throw JSEngineError.message("render must return a component tree (got undefined)")
        }
        return str
    }

    // MARK: JSModuleLoaderDelegate

    @objc(context:fetchModuleForIdentifier:withResolveHandler:andRejectHandler:)
    func context(_ context: JSContext!, fetchModuleForIdentifier identifier: JSValue!,
                 withResolveHandler resolve: JSValue!, andRejectHandler reject: JSValue!) {
        let id = identifier.toString() ?? ""
        func fail(_ msg: String) {
            loadError = msg
            reject.call(withArguments: [JSValue(newErrorFromMessage: msg, in: context) as Any])
        }
        func supply(_ source: String, _ url: URL) {
            do {
                let s = try makeModuleScript(source, url)
                resolve.call(withArguments: [s])
            } catch { fail("failed to parse module \(url.lastPathComponent): \(error)") }
        }
        if id == Self.sdkSpecifier || id == "file://" + Self.sdkSpecifier {
            supply(SDKModule.source, URL(string: "file://" + Self.sdkSpecifier)!)
            return
        }
        guard let url = URL(string: id), url.scheme == "file" else {
            fail("import “\(id)” is forbidden: only \"widgee\" and relative files inside the widget folder are allowed")
            return
        }
        let path = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard path.path.hasPrefix(rootPath) else {
            fail("import “\(id)” is forbidden: path escapes the widget folder")
            return
        }
        if path.lastPathComponent == Self.entryName, let src = entrySource { supply(src, path); return }
        guard let data = try? Data(contentsOf: path), let source = String(data: data, encoding: .utf8) else {
            fail("could not read module \(path.lastPathComponent)")
            return
        }
        supply(Self.rewriteSDKImports(source), path)
    }

    /// Заменяет строковый литерал "widgee" в `from "widgee"`, `import "widgee"`, `import("widgee")`.
    static func rewriteSDKImports(_ source: String) -> String {
        guard source.contains("widgee") else { return source }
        let pattern = #"(\bfrom\s*|\bimport\s*\(?\s*)(["'])widgee\2"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return re.stringByReplacingMatches(in: source, range: range, withTemplate: "$1\"\(sdkSpecifier)\"")
    }

    private var entrySource: String?
}
