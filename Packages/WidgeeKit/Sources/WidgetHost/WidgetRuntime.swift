import Foundation
import WidgeeCore

public enum WidgetState: Equatable, Sendable {
    case loaded
    case running
    case failed(String)
}

public enum WidgetError: Error, Equatable, CustomStringConvertible, Sendable {
    case failed(String)
    public var description: String { if case .failed(let m) = self { m } else { "" } }
}

/// Контекст, который уходит в JS как `ctx`.
public struct RenderContext: Codable, Equatable, Sendable {
    public struct Size: Codable, Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var sizeClass: SizeClass
        public init(width: Double, height: Double, sizeClass: SizeClass) {
            self.width = width; self.height = height; self.sizeClass = sizeClass
        }
    }
    public var size: Size
    public var theme: Theme
    public var settings: [String: JSONValue]
    public var data: JSONValue

    public init(size: Size, theme: Theme = Theme(), settings: [String: JSONValue] = [:], data: JSONValue = .object([:])) {
        self.size = size; self.theme = theme; self.settings = settings; self.data = data
    }
}

public struct WidgetLimits: Sendable {
    public var maxDepth = 32
    public var maxNodes = 2000
    public var maxJSONBytes = 1_000_000
    public init() {}
}

/// Один виджет = один JSContext в собственной JSContextGroup и на собственной очереди.
///
/// Таймаут: `JSContextGroupSetExecutionTimeLimit` (приватный API JSC, через dlsym) прерывает JS внутри
/// группы по сторожевому таймеру, в том числе `while(true){}`. Резервный путь: если JSC не прервался
/// за `hardGrace`, runtime помечается failed, а зависшая очередь/контекст бросаются (утечка потока),
/// не затрагивая другие runtime — у каждого своя очередь и группа.
public final class WidgetRuntime: @unchecked Sendable {
    public typealias Logger = @Sendable (_ level: String, _ message: String) -> Void

    public let directory: URL
    public let renderTimeout: Double
    public let loadTimeout: Double
    public let hardGrace: Double
    public let limits: WidgetLimits
    private let hostSDK: String
    private let logger: Logger

    private let lock = NSLock()
    private var _state: WidgetState = .loaded
    private var _manifest: WidgetManifest?
    private var engine: JSEngine?
    private var _sources: [SourceSpec] = []
    private var inFlight = 0
    private var generation = 0

    public var state: WidgetState { lock.withLock { stateLocked } }
    public var manifest: WidgetManifest? { lock.withLock { _manifest } }

    /// Источники данных, объявленные виджетом (после успешной загрузки).
    public var sources: [SourceSpec] { lock.withLock { _sources } }

    private var stateLocked: WidgetState {
        if case .failed = _state { return _state }
        return inFlight > 0 ? .running : .loaded
    }

    private init(directory: URL, hostSDK: String, renderTimeout: Double, loadTimeout: Double,
                 hardGrace: Double, limits: WidgetLimits, logger: @escaping Logger) {
        self.directory = directory; self.hostSDK = hostSDK
        self.renderTimeout = renderTimeout; self.loadTimeout = loadTimeout
        self.hardGrace = hardGrace; self.limits = limits; self.logger = logger
    }

    /// Загружает виджет из папки (manifest.json + widget.js). Ошибки отражаются в `state == .failed`.
    public static func load(directory: URL, hostSDK: String = WidgeeCore.sdkVersion,
                            settings: [String: JSONValue] = [:],
                            renderTimeout: Double = 0.1, loadTimeout: Double = 1.0, hardGrace: Double = 1.0,
                            limits: WidgetLimits = WidgetLimits(),
                            logger: @escaping Logger = { _, _ in }) async -> WidgetRuntime {
        let rt = WidgetRuntime(directory: directory, hostSDK: hostSDK, renderTimeout: renderTimeout,
                               loadTimeout: loadTimeout, hardGrace: hardGrace, limits: limits, logger: logger)
        await rt.start(settings: settings)
        return rt
    }

    /// Пересоздаёт контекст (hot reload / кнопка «перезапустить»); состояние JS сбрасывается.
    public func restart(settings: [String: JSONValue] = [:]) async { await start(settings: settings) }

    private static func encode(_ settings: [String: JSONValue]) -> String {
        String(decoding: (try? JSONEncoder().encode(settings)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// Заново вычисляет `sources` (функцию `(settings) => ({...})` или объект) для новых настроек.
    /// Права проверяются на итоговых URL. Ошибка переводит runtime в `failed`.
    @discardableResult
    public func resolveSources(settings: [String: JSONValue]) async throws -> [SourceSpec] {
        let (eng, manifest, gen): (JSEngine, WidgetManifest, Int) = try lock.withLock {
            if case .failed(let r) = _state { throw WidgetError.failed(r) }
            guard let e = engine, let m = _manifest else { throw WidgetError.failed("widget is not loaded") }
            return (e, m, generation)
        }
        do {
            let json = Self.encode(settings)
            let t = loadTimeout
            let srcJSON = try await execute(on: eng, timeout: t) { try $0.readSources(settingsJSON: json, timeout: t) }
            let specs = try SourceSpec.parse(json: srcJSON, permissions: manifest.permissions)
            lock.withLock { if generation == gen { _sources = specs } }
            return specs
        } catch {
            let reason = (error as? WidgetError)?.description ?? "\(error)"
            lock.withLock { if generation == gen { _state = .failed(reason) } }
            logger("error", "widget: sources: \(reason)")
            throw WidgetError.failed(reason)
        }
    }

    private func start(settings: [String: JSONValue]) async {
        let gen: Int = lock.withLock { generation += 1; engine = nil; _sources = []; inFlight = 0; _state = .loaded; return generation }
        do {
            let data: Data
            do { data = try Data(contentsOf: directory.appendingPathComponent("manifest.json")) }
            catch { throw WidgetManifestError.unreadable(error.localizedDescription) }
            let manifest = try WidgetManifest.parse(data, hostSDK: hostSDK)
            let logger = self.logger
            let eng = JSEngine(root: directory, logger: logger)
            try await execute(on: eng, timeout: loadTimeout) { try $0.loadWidget(timeout: self.loadTimeout) }
            let sjson = Self.encode(settings), lt = loadTimeout
            let srcJSON = try await execute(on: eng, timeout: loadTimeout) { try $0.readSources(settingsJSON: sjson, timeout: lt) }
            let specs = try SourceSpec.parse(json: srcJSON, permissions: manifest.permissions)
            let ok: Bool = lock.withLock {
                guard generation == gen else { return false }
                _manifest = manifest; _sources = specs; engine = eng; return true
            }
            if !ok { return }
        } catch {
            let reason = "\(error)"
            lock.withLock { if generation == gen { _state = .failed(reason) } }
            logger("error", "widget is not loaded: \(reason)")
        }
    }

    public func render(_ ctx: RenderContext) async throws -> UINode {
        let (eng, gen): (JSEngine, Int) = try lock.withLock {
            if case .failed(let r) = _state { throw WidgetError.failed(r) }
            guard let e = engine else { throw WidgetError.failed("widget is not loaded") }
            inFlight += 1
            return (e, generation)
        }
        defer { lock.withLock { if generation == gen { inFlight -= 1 } } }
        do {
            let json = String(decoding: try JSONEncoder().encode(ctx), as: UTF8.self)
            let out = try await execute(on: eng, timeout: renderTimeout) {
                try $0.invokeRender(json: json, timeout: self.renderTimeout)
            }
            return try Self.parseTree(out, limits: limits)
        } catch {
            let reason = (error as? WidgetError)?.description ?? "\(error)"
            lock.withLock { if generation == gen { _state = .failed(reason) } }
            logger("error", reason)
            throw WidgetError.failed(reason)
        }
    }

    // MARK: исполнение с жёстким дедлайном

    private final class Once<T: Sendable>: @unchecked Sendable {
        private let l = NSLock(); private var done = false
        let cont: CheckedContinuation<T, Error>
        init(_ c: CheckedContinuation<T, Error>) { cont = c }
        func finish(_ r: Result<T, Error>) {
            let first = l.withLock { let f = !done; done = true; return f }
            if first { cont.resume(with: r) }
        }
    }

    private func execute<T: Sendable>(on eng: JSEngine, timeout: Double,
                                      _ work: @escaping @Sendable (JSEngine) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            let once = Once(c)
            eng.queue.async {
                once.finish(Result { try work(eng) }.mapError { WidgetError.failed("\($0)") })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + hardGrace) {
                once.finish(.failure(WidgetError.failed("JS hung and did not stop at the timeout (\(Int(timeout * 1000)) ms); context discarded")))
            }
        }
    }

    // MARK: проверка дерева

    static func parseTree(_ json: String, limits: WidgetLimits) throws -> UINode {
        guard json.utf8.count <= limits.maxJSONBytes else {
            throw WidgetError.failed("tree is too large (> \(limits.maxJSONBytes) bytes)")
        }
        let node: UINode
        do { node = try JSONDecoder().decode(UINode.self, from: Data(json.utf8)) }
        catch { throw WidgetError.failed("render returned an invalid tree: \(error.localizedDescription)") }
        var count = 0
        func check(_ n: UINode, _ depth: Int) throws {
            count += 1
            guard depth <= limits.maxDepth else { throw WidgetError.failed("tree depth > \(limits.maxDepth)") }
            guard count <= limits.maxNodes else { throw WidgetError.failed("nodes in tree > \(limits.maxNodes)") }
            guard SDKModule.componentNames.contains(n.type) else {
                throw WidgetError.failed("unknown component type “\(n.type)”")
            }
            for c in n.children { try check(c, depth + 1) }
        }
        try check(node, 1)
        return node
    }
}
