import Testing
import Foundation
import WidgeeCore
@testable import WidgetHost

private let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/BuiltinWidgets")

private let widgetIDs: [String] = {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { !$0.hasPrefix(".") }
        .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }
        .sorted()
}()

/// Виджеты с fit-коробками (system-monitor задаёт размеры через size).
private let fitWidgets: Set<String> = [
    "clock", "weather", "battery", "storage", "network", "calendar", "world-clock", "countdown", "day-progress",
]

private let sizes: [(String, Double, Double, SizeClass)] = [
    ("S", 170, 170, .small), ("M", 360, 170, .medium), ("L", 360, 360, .large), ("XL", 720, 380, .extraLarge),
]

private func json(_ s: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
}

private let stubs: [JSONValue] = [
    json(#"""
    {"battery":{"level":0.8,"isCharging":true,"isPluggedIn":true},"disk":{"free":2e11,"total":5e11},
     "network":{"downBytesPerSec":2345678,"upBytesPerSec":12345},"now":{"now":1788000000000,"tick":1}}
    """#),
    json(#"{"battery":null,"disk":null,"network":null,"now":null}"#),
    json(#"{}"#),
]

private func allNodes(_ n: UINode) -> [UINode] { [n] + n.children.flatMap(allNodes) }

private func number(_ v: JSONValue?) -> Double? {
    if case .number(let d)? = v { return d }
    return nil
}

private func isFit(_ n: UINode) -> Bool {
    if case .bool(true)? = n.props["fit"] { return true }
    return false
}

private func isFitText(_ n: UINode) -> Bool { (n.type == "Text" || n.type == "DigitalClock") && isFit(n) }

/// Дерево без меняющихся со временем данных (тексты и значения): только раскладка и размеры.
private func layout(_ n: UINode) -> UINode {
    var n = n
    for k in ["text", "value", "values"] { n.props[k] = nil }
    n.children = n.children.map(layout)
    return n
}

private func validFit(_ n: UINode) -> Bool {
    isFitText(n) && (number(n.props["width"]) ?? 0) > 0 && (number(n.props["height"]) ?? 0) > 0
}

@Suite struct FitTextTests {
    @Test(arguments: widgetIDs)
    func fitBoxesInAutoAndManual(_ id: String) async throws {
        let m = try WidgetManifest.parse(Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("manifest.json")))
        var defaults: [String: JSONValue] = [:]
        for f in m.settings { if let d = f.default { defaults[f.key] = d } }
        var configs: [(String, [String: JSONValue])] = [("default", defaults)]
        for v in m.variants { configs.append((v.key, defaults.merging(v.settings) { _, new in new })) }
        for (name, settings) in configs {
            let rt = await WidgetRuntime.load(directory: root.appendingPathComponent(id), settings: settings,
                                              renderTimeout: 5, loadTimeout: 5)
            #expect(rt.state == .loaded, "\(id)/\(name): \(rt.state)")
            let isQuote = id == "note" && settings["style"]?.stringValue == "quote"
            for a in ContentAlignment.allCases {
                for sz in sizes {
                    for (i, data) in stubs.enumerated() {
                        let tag = "\(id)/\(name) \(a) \(sz.0) data\(i)"
                        let size = RenderContext.Size(width: sz.1, height: sz.2, sizeClass: sz.3)

                        // Auto: textScale == nil.
                        let auto = try await rt.render(RenderContext(size: size, theme: Theme(alignment: a, textScale: nil),
                                                                    settings: settings, data: data))
                        let nodes = allNodes(auto)
                        if fitWidgets.contains(id) && !isQuote {
                            #expect(nodes.contains(where: validFit), "\(tag): no fit node in auto")
                        }
                        for n in nodes where isFitText(n) {
                            #expect(validFit(n), "\(tag): fit node without positive width/height")
                        }
                        for stack in nodes where stack.type == "VStack" {
                            let sum = stack.children.filter(isFitText).reduce(0.0) { $0 + (number($1.props["height"]) ?? 0) }
                            #expect(sum <= sz.2 * 1.08, "\(tag): fit boxes \(sum) > height \(sz.2)")
                        }

                        // Manual: раскладка та же, процент применяет хост (TextScalePass), а не виджет.
                        for scale in [1.5, 0.5] {
                            let manual = try await rt.render(RenderContext(size: size, theme: Theme(alignment: a, textScale: scale),
                                                                          settings: settings, data: data))
                            #expect(layout(manual) == layout(auto), "\(tag): layout depends on textScale \(scale)")
                        }
                    }
                }
            }
        }
    }
}
