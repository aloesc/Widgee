import Testing
import Foundation
import WidgeeCore
@testable import WidgetHost

private let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/BuiltinWidgets")

private let legacy: Set<String> = ["clock", "system-monitor", "weather"]
private let categories: Set<String> = ["today", "weather", "battery", "clock", "system", "other"]

private let newWidgetIDs: [String] = {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { !legacy.contains($0) && !$0.hasPrefix(".") }
        .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }
        .sorted()
}()

private func json(_ s: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
}

private let sizes: [(String, Double, Double, SizeClass)] = [
    ("S", 170, 170, .small), ("M", 360, 170, .medium), ("L", 360, 360, .large), ("XL", 720, 380, .extraLarge),
]

private let stubs: [JSONValue] = [
    json(#"""
    {"battery":{"level":0.8,"isCharging":true,"isPluggedIn":true},"disk":{"free":2e11,"total":5e11},
     "network":{"downBytesPerSec":2345678,"upBytesPerSec":12345},"now":{"now":1788000000000,"tick":1}}
    """#),
    json(#"""
    {"battery":{"level":0.07,"isCharging":false,"isPluggedIn":false},"disk":{"free":1e9,"total":5e11},
     "network":{"downBytesPerSec":0,"upBytesPerSec":0},"now":{"now":1798675199000,"tick":2}}
    """#),
    json(#"{"battery":null,"disk":null,"network":null,"now":null}"#),
    json(#"{}"#),
]

private func manifest(_ id: String) throws -> WidgetManifest {
    try WidgetManifest.parse(Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("manifest.json")))
}

private func allNodes(_ n: UINode) -> [UINode] { [n] + n.children.flatMap(allNodes) }

@Suite struct NewBuiltinWidgetsTests {
    @Test func newWidgetsAreDiscovered() {
        #expect(!newWidgetIDs.isEmpty)
    }

    @Test(arguments: newWidgetIDs)
    func manifestIsValid(_ id: String) throws {
        let m = try manifest(id)
        #expect(m.id == id)
        #expect(m.version == "0.1.0" && m.author == "Widgee")
        #expect((2...4).contains(m.variants.count), "\(id): \(m.variants.count) variants")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("manifest.json"))) as? [String: Any]
        #expect(categories.contains(raw?["category"] as? String ?? ""), "\(id): category")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(id).appendingPathComponent("widget.js").path))
        for f in m.settings where f.type == "select" { #expect(f.options?.contains(f.default?.stringValue ?? "") == true, "\(id).\(f.key) default") }
    }

    @Test(arguments: newWidgetIDs)
    func rendersEverywhere(_ id: String) async throws {
        let m = try manifest(id)
        var defaults: [String: JSONValue] = [:]
        for f in m.settings { if let d = f.default { defaults[f.key] = d } }
        var configs: [(String, [String: JSONValue])] = [("default", defaults)]
        for v in m.variants { configs.append((v.key, defaults.merging(v.settings) { _, new in new })) }
        for (name, settings) in configs {
            let rt = await WidgetRuntime.load(directory: root.appendingPathComponent(id), settings: settings,
                                              renderTimeout: 5, loadTimeout: 5)
            #expect(rt.state == .loaded, "\(id)/\(name): \(rt.state)")
            for a in ContentAlignment.allCases {
                for sz in sizes {
                    for (i, data) in stubs.enumerated() {
                        let ctx = RenderContext(size: .init(width: sz.1, height: sz.2, sizeClass: sz.3),
                                                theme: Theme(alignment: a), settings: settings, data: data)
                        let tree = try await rt.render(ctx)
                        #expect(!tree.type.isEmpty && !tree.type.hasPrefix("?"), "\(id)/\(name) \(a) \(sz.0) data\(i)")
                        #expect(allNodes(tree).count > 1, "\(id)/\(name) \(a) \(sz.0) data\(i): empty tree")
                        #expect(allNodes(tree).contains { $0.type == "Text" || $0.type == "Image" || $0.type == "DigitalClock" },
                                "\(id)/\(name) \(a) \(sz.0) data\(i): no content")
                    }
                }
            }
        }
    }
}
