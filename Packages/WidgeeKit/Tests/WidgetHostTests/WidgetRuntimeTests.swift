import Testing
import Foundation
import WidgeeCore
@testable import WidgetHost

private let goodManifest = """
{"id":"t.w","name":"T","version":"1.0.0","author":"a","sdk":"0.1.0","sizes":["S","M"],
 "permissions":{"system":["cpu"],"network":["api.example.com"]},
 "settings":[{"key":"label","type":"string","label":"Label","default":"hi"}]}
"""

private let goodJS = """
import { defineWidget, VStack, Text } from "widgee";
export default defineWidget({
  render(ctx) {
    console.log("render", ctx.size.sizeClass);
    return VStack({ spacing: 4 }, Text({ value: ctx.settings.label + ":" + ctx.size.width }));
  }
});
"""

private func makeWidget(manifest: String = goodManifest, js: String = goodJS,
                        extra: [String: String] = [:]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widgee-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try js.write(to: dir.appendingPathComponent("widget.js"), atomically: true, encoding: .utf8)
    for (k, v) in extra { try v.write(to: dir.appendingPathComponent(k), atomically: true, encoding: .utf8) }
    return dir
}

private let ctx = RenderContext(size: .init(width: 170, height: 170, sizeClass: .small),
                                settings: ["label": .string("hi")])

private final class Logs: @unchecked Sendable {
    private let l = NSLock(); private var items: [String] = []
    func add(_ s: String) { l.withLock { items.append(s) } }
    var all: [String] { l.withLock { items } }
}

private func failure(_ rt: WidgetRuntime) -> String? {
    if case .failed(let r) = rt.state { r } else { nil }
}

@Suite struct WidgetRuntimeTests {
    @Test func loadsValidWidgetAndRenders() async throws {
        let logs = Logs()
        let rt = await WidgetRuntime.load(directory: try makeWidget(), logger: { l, m in logs.add("\(l):\(m)") })
        #expect(rt.state == .loaded, "\(rt.state)")
        #expect(rt.manifest?.id == "t.w")
        let tree = try await rt.render(ctx)
        #expect(tree.type == "VStack")
        #expect(tree.props["spacing"] == .number(4))
        #expect(tree.children.first?.props["value"] == .string("hi:170"))
        #expect(logs.all.contains("log:render small"))
        #expect(rt.state == .loaded)
    }

    @Test func relativeImportInsideFolderWorks() async throws {
        let js = """
        import { defineWidget, Text } from "widgee";
        import { label } from "./lib/helper.js";
        export default defineWidget({ render() { return Text({ value: label }); } });
        """
        let dir = try makeWidget(js: js)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "export const label = 'from-helper';".write(to: dir.appendingPathComponent("lib/helper.js"), atomically: true, encoding: .utf8)
        let rt = await WidgetRuntime.load(directory: dir)
        #expect(rt.state == .loaded, "\(rt.state)")
        let tree = try await rt.render(ctx)
        #expect(tree.props["value"] == .string("from-helper"))
    }

    @Test(arguments: [
        ("import fs from \"fs\";", "fs"),
        ("import x from \"../x.js\";", "x.js"),
        ("import x from \"https://evil.example/x.js\";", "https"),
        ("import x from \"/etc/passwd\";", "passwd"),
        ("import x from \"file:///etc/hosts\";", "hosts"),
    ])
    func rejectsForbiddenImports(line: String, needle: String) async throws {
        let js = line + "\nexport default { render() { return { type: 'Spacer', props: {}, children: [] }; } };"
        let rt = await WidgetRuntime.load(directory: try makeWidget(js: js))
        let reason = try #require(failure(rt), "widget must be failed")
        #expect(reason.contains("forbidden") || reason.contains(needle), "\(reason)")
    }

    @Test func sandboxHasNoTimersFilesNetwork() async throws {
        let js = """
        import { defineWidget, Text } from "widgee";
        const names = ["setTimeout","setInterval","fetch","require","process","XMLHttpRequest","Buffer"];
        export default defineWidget({ render() {
          return Text({ value: names.map(n => typeof globalThis[n]).join(",") });
        } });
        """
        let rt = await WidgetRuntime.load(directory: try makeWidget(js: js))
        let tree = try await rt.render(ctx)
        #expect(tree.props["value"] == .string(Array(repeating: "undefined", count: 7).joined(separator: ",")))
    }

    @Test func infiniteLoopFailsFastOthersKeepWorking() async throws {
        let hang = """
        import { defineWidget } from "widgee";
        export default defineWidget({ render() { while (true) {} } });
        """
        let bad = await WidgetRuntime.load(directory: try makeWidget(js: hang))
        let good = await WidgetRuntime.load(directory: try makeWidget())
        let start = Date()
        await #expect(throws: WidgetError.self) { try await bad.render(ctx) }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 3, "elapsed \(elapsed)")
        #expect(failure(bad) != nil)
        #expect(try await good.render(ctx).type == "VStack")
        #expect(good.state == .loaded)
        // после failed render не выполняется, restart не лечит сам код, но сбрасывает состояние
        await #expect(throws: WidgetError.self) { try await bad.render(ctx) }
    }

    @Test func infiniteLoopAtModuleTopLevelFailsLoad() async throws {
        let js = "export default { render() { return null; } };\nwhile (true) {}"
        let rt = await WidgetRuntime.load(directory: try makeWidget(js: js), loadTimeout: 0.3)
        #expect(failure(rt) != nil)
    }

    @Test func renderExceptionMarksFailedAndRestartRecovers() async throws {
        let js = """
        import { defineWidget } from "widgee";
        export default defineWidget({ render(ctx) { throw new Error("boom"); } });
        """
        let dir = try makeWidget(js: js)
        let rt = await WidgetRuntime.load(directory: dir)
        await #expect(throws: WidgetError.self) { try await rt.render(ctx) }
        let reason = try #require(failure(rt))
        #expect(reason.contains("boom"))
        try goodJS.write(to: dir.appendingPathComponent("widget.js"), atomically: true, encoding: .utf8)
        await rt.restart()
        #expect(rt.state == .loaded)
        #expect(try await rt.render(ctx).type == "VStack")
    }

    @Test func invalidTreesAreRejected() async throws {
        let cases = [
            "return { type: 'Nope', props: {}, children: [] };",
            "return 42;",
            "return undefined;",
            "return { type: 'Text', props: {}, children: 'x' };",
            "let n = { type: 'Spacer', props: {}, children: [] }; for (let i = 0; i < 100; i++) n = { type: 'VStack', props: {}, children: [n] }; return n;",
            "return { type: 'VStack', props: {}, children: Array.from({length: 5000}, () => ({ type: 'Spacer', props: {}, children: [] })) };",
        ]
        for body in cases {
            let js = "export default { render(ctx) { \(body) } };"
            let rt = await WidgetRuntime.load(directory: try makeWidget(js: js))
            await #expect(throws: WidgetError.self, "\(body)") { try await rt.render(ctx) }
            #expect(failure(rt) != nil, "\(body)")
        }
    }

    @Test func missingDefaultExportFailsLoad() async throws {
        let rt = await WidgetRuntime.load(directory: try makeWidget(js: "export const x = 1;"))
        #expect(failure(rt) != nil)
    }
}

@Suite struct WidgetManifestTests {
    @Test func parsesValid() throws {
        let m = try WidgetManifest.parse(Data(goodManifest.utf8))
        #expect(m.permissions.network == ["api.example.com"])
        #expect(m.settings.first?.default == .string("hi"))
    }

    @Test(arguments: [
        "{ not json",
        #"{"id":"a","name":"n","version":"1.0","author":"a","sdk":"0.1.0"}"#,
        #"{"id":"a","name":"n","version":"1.0.0","author":"a"}"#,
        #"{"id":"","name":"n","version":"1.0.0","author":"a","sdk":"0.1.0"}"#,
        #"{"id":"a","name":"n","version":"1.0.0","author":"a","sdk":"0.1.0","sizes":["XXL"]}"#,
        #"{"id":"a","name":"n","version":"1.0.0","author":"a","sdk":"0.1.0","permissions":{"network":["http://x.com/path"]}}"#,
        #"{"id":"a","name":"n","version":"1.0.0","author":"a","sdk":"0.1.0","settings":[{"key":"k","type":"weird","label":"l"}]}"#,
    ])
    func rejectsInvalid(json: String) {
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(Data(json.utf8)) }
    }

    @Test func parsesCityAndSelectOptions() throws {
        let json = #"""
        {"id":"a","name":"n","version":"1.0.0","sdk":"0.1.0","settings":[
          {"key":"c","type":"city","label":"City","default":{"name":"Moscow","latitude":55.7558,"longitude":37.6176}},
          {"key":"u","type":"select","label":"U","default":"c","options":["c","f"]}]}
        """#
        let m = try WidgetManifest.parse(Data(json.utf8))
        #expect(m.settings[1].options == ["c", "f"])
        let city = CitySetting(json: m.settings[0].default)
        #expect(city?.name == "Moscow")
        #expect(city?.latitude == 55.7558)
        #expect(CitySetting(json: city?.json) == city)
    }

    @Test(arguments: [
        #"{"key":"c","type":"city","label":"C","default":"Moscow"}"#,
        #"{"key":"c","type":"city","label":"C","default":{"name":"X","latitude":91,"longitude":0}}"#,
        #"{"key":"c","type":"city","label":"C","default":{"name":"","latitude":1,"longitude":0}}"#,
        #"{"key":"c","type":"city","label":"C","default":{"name":"X","latitude":1}}"#,
        #"{"key":"u","type":"select","label":"U","options":[]}"#,
        #"{"key":"u","type":"select","label":"U","options":[1]}"#,
    ])
    func rejectsInvalidCityAndOptions(field: String) {
        let json = #"{"id":"a","name":"n","version":"1.0.0","sdk":"0.1.0","settings":[\#(field)]}"#
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(Data(json.utf8)) }
    }

    @Test func parsesColorAndShowIf() throws {
        let json = #"""
        {"id":"a","name":"n","version":"1.0.0","sdk":"0.1.0","settings":[
          {"key":"mode","type":"select","label":"M","default":"a","options":["a","b"]},
          {"key":"c","type":"color","label":"C","default":"#0a84FF","showIf":{"key":"mode","equals":"b"}}]}
        """#
        let m = try WidgetManifest.parse(Data(json.utf8))
        #expect(m.settings[1].showIf == SettingCondition(key: "mode", equals: .string("b")))
        let c = try #require(m.settings[1].showIf)
        #expect(!c.isSatisfied(values: [:], fields: m.settings))
        #expect(c.isSatisfied(values: ["mode": .string("b")], fields: m.settings))
    }

    @Test(arguments: [
        ##"{"key":"c","type":"color","label":"C"}"##,
        ##"{"key":"c","type":"color","label":"C","default":"#12345"}"##,
        ##"{"key":"c","type":"color","label":"C","default":"0A84FF"}"##,
        ##"{"key":"c","type":"color","label":"C","default":"#GGGGGG"}"##,
        ##"{"key":"c","type":"color","label":"C","default":5}"##,
        ##"{"key":"c","type":"boolean","label":"C","showIf":{"key":"nope","equals":true}}"##,
        ##"{"key":"c","type":"boolean","label":"C","showIf":{"key":"c","equals":true}}"##,
        ##"{"key":"c","type":"boolean","label":"C","showIf":{"key":"c"}}"##,
    ])
    func rejectsInvalidColorAndShowIf(field: String) {
        let json = ##"{"id":"a","name":"n","version":"1.0.0","sdk":"0.1.0","settings":[\##(field)]}"##
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(Data(json.utf8)) }
    }

    @Test func sdkCompatibility() throws {
        func m(_ sdk: String) -> Data {
            Data(#"{"id":"a","name":"n","version":"1.0.0","author":"a","sdk":"\#(sdk)"}"#.utf8)
        }
        _ = try WidgetManifest.parse(m("0.1.0"), hostSDK: "0.1.0")
        _ = try WidgetManifest.parse(m("0.1.5"), hostSDK: "0.2.0")
        #expect(throws: WidgetManifestError.incompatibleSDK(required: "0.3.0", host: "0.2.0")) {
            try WidgetManifest.parse(m("0.3.0"), hostSDK: "0.2.0")
        }
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(m("1.0.0"), hostSDK: "0.2.0") }
    }

    @Test func invalidManifestFailsRuntimeWithoutCrash() async throws {
        let rt = await WidgetRuntime.load(directory: try makeWidget(manifest: "{}"))
        #expect(failure(rt)?.contains("manifest.json") == true)
        let rt2 = await WidgetRuntime.load(directory: try makeWidget(manifest: goodManifest.replacingOccurrences(of: "0.1.0\",\"sizes", with: "9.0.0\",\"sizes")))
        #expect(failure(rt2)?.contains("sdk") == true, "\(rt2.state)")
    }

    @Test func semver() {
        #expect(SemVer("1.2.3") == SemVer(major: 1, minor: 2, patch: 3))
        #expect(SemVer("1.2.3-beta.1+b5") != nil)
        #expect(SemVer("1.2") == nil)
        #expect(SemVer("01.2.3") == nil)
        #expect(SemVer("a.b.c") == nil)
    }
}
