import Testing
import Foundation
import WidgeeCore
@testable import WidgetHost

private let builtinRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/BuiltinWidgets")

private func json(_ s: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
}

private let sizes: [(String, Double, Double, SizeClass)] = [
    ("S", 170, 170, .small), ("M", 360, 170, .medium), ("XL", 720, 380, .extraLarge),
]

private let systemData = json(#"""
{"cpu":{"total":0.42},"ram":{"used":8e9,"total":16e9},"disk":{"free":2e11,"total":5e11},
 "network":{"downBytesPerSec":12345,"upBytesPerSec":2345},"battery":{"level":0.8,"isCharging":true}}
"""#)
private let weatherData = json(#"""
{"w":{"stale":false,"value":{"current":{"time":"2026-01-01T10:00","temperature_2m":3.4,"weather_code":2,"is_day":1},
 "hourly":{"time":["2026-01-01T10:00","2026-01-01T11:00","2026-01-01T12:00","2026-01-01T13:00","2026-01-01T14:00","2026-01-01T15:00"],
  "temperature_2m":[3,4,5,5,4,3],"weather_code":[2,2,3,3,61,61]},
 "daily":{"time":["2026-01-01","2026-01-02","2026-01-03","2026-01-04","2026-01-05"],"weather_code":[2,3,61,0,1],
  "temperature_2m_max":[5,6,4,7,8],"temperature_2m_min":[-1,0,1,2,3]}}}}
"""#)

private func data(_ id: String, empty: Bool) -> JSONValue {
    if empty {
        switch id {
        case "clock": return json(#"{"now":null}"#)
        case "system-monitor": return json(#"{"cpu":null,"ram":null,"disk":null,"network":null,"battery":null}"#)
        default: return json(#"{"w":null}"#)
        }
    }
    switch id {
    case "clock": return json(#"{"now":{"now":1767261600000}}"#)
    case "system-monitor": return systemData
    default: return weatherData
    }
}

private func load(_ id: String, _ settings: [String: JSONValue] = [:]) async -> WidgetRuntime {
    await WidgetRuntime.load(directory: builtinRoot.appendingPathComponent(id), settings: settings,
                             renderTimeout: 5, loadTimeout: 5)
}

private func renderTree(_ rt: WidgetRuntime, _ id: String, _ a: ContentAlignment, _ sz: (String, Double, Double, SizeClass),
                        settings: [String: JSONValue], empty: Bool = false) async throws -> UINode {
    let ctx = RenderContext(size: .init(width: sz.1, height: sz.2, sizeClass: sz.3),
                            theme: Theme(alignment: a), settings: settings, data: data(id, empty: empty))
    return try await rt.render(ctx)
}

private func allNodes(_ n: UINode) -> [UINode] { [n] + n.children.flatMap(allNodes) }

@Suite struct BuiltinWidgetsAlignmentTests {
    @Test func allBuiltinWidgetsRenderForEveryAlignmentAndSize() async throws {
        let variants: [(String, [String: JSONValue])] = [
            ("clock", [:]), ("clock", ["style": .string("analog")]),
            ("system-monitor", [:]), ("system-monitor", ["layout": .string("rings")]),
            ("system-monitor", ["layout": .string("graphs")]), ("weather", [:]),
        ]
        for (id, settings) in variants {
            let rt = await load(id, settings)
            #expect(rt.state == .loaded, "\(id): \(rt.state)")
            for a in ContentAlignment.allCases {
                for sz in sizes {
                    for empty in [false, true] {
                        let tree = try await renderTree(rt, id, a, sz, settings: settings, empty: empty)
                        #expect(!tree.type.isEmpty, "\(id) \(a) \(sz.0)")
                    }
                }
            }
        }
    }

    @Test func digitalClockHonoursAlignment() async throws {
        let rt = await load("clock")
        let sz = sizes[1]
        var roots: [ContentAlignment: UINode] = [:]
        for a in ContentAlignment.allCases { roots[a] = try await renderTree(rt, "clock", a, sz, settings: [:]) }
        #expect(roots[.auto]?.props["alignment"] == .string("center"))
        #expect(roots[.center]?.props["alignment"] == .string("center"))
        #expect(roots[.left]?.props["alignment"] == .string("leading"))
        #expect(roots[.right]?.props["alignment"] == .string("trailing"))
        #expect(roots[.left] != roots[.right])
        let aligns = { (n: UINode) in allNodes(n).filter { $0.type == "Text" }.compactMap { $0.props["align"] } }
        #expect(aligns(roots[.left]!).allSatisfy { $0 == .string("leading") } && !aligns(roots[.left]!).isEmpty)
        #expect(aligns(roots[.right]!).allSatisfy { $0 == .string("trailing") })
    }

    @Test func wideAnalogClockMirrorsForRight() async throws {
        let s: [String: JSONValue] = ["style": .string("analog")]
        let rt = await load("clock", s)
        let xl = sizes[2]
        let left = try await renderTree(rt, "clock", .left, xl, settings: s)
        let right = try await renderTree(rt, "clock", .right, xl, settings: s)
        #expect(left.children.first?.type == "AnalogClock")
        #expect(right.children.last?.type == "AnalogClock")
    }
}

@Suite struct SystemMonitorColorTests {
    static let modes = ["Per metric", "Single color", "By fill level", "Custom per metric"]
    static let layouts = ["bars", "rings", "graphs"]
    static let xl = sizes[2]

    private func settings(_ mode: String, _ layout: String) -> [String: JSONValue] {
        ["colorMode": .string(mode), "layout": .string(layout), "singleColor": .string("#112233")]
    }

    private func colors(_ n: UINode) -> [String] {
        allNodes(n).filter { ["LinearBar", "Ring", "Sparkline"].contains($0.type) }
            .compactMap { $0.props["color"]?.stringValue }
    }

    private func render(_ rt: WidgetRuntime, _ s: [String: JSONValue], _ d: JSONValue,
                        _ sz: (String, Double, Double, SizeClass) = SystemMonitorColorTests.xl) async throws -> UINode {
        try await rt.render(RenderContext(size: .init(width: sz.1, height: sz.2, sizeClass: sz.3),
                                          theme: Theme(), settings: s, data: d))
    }

    @Test func rendersInAllModesAndLayouts() async throws {
        for mode in Self.modes {
            for layout in Self.layouts {
                let s = settings(mode, layout)
                let rt = await load("system-monitor", s)
                #expect(rt.state == .loaded, "\(mode) \(layout): \(rt.state)")
                for sz in sizes {
                    for empty in [false, true] {
                        let tree = try await renderTree(rt, "system-monitor", .auto, sz, settings: s, empty: empty)
                        #expect(!tree.type.isEmpty, "\(mode) \(layout) \(sz.0)")
                        if empty { #expect(colors(tree).allSatisfy { $0 == "#8E8E93" }, "\(mode) \(layout) null") }
                    }
                }
            }
        }
    }

    @Test func singleModeUsesOneColor() async throws {
        for layout in Self.layouts {
            let s = settings("Single color", layout)
            let rt = await load("system-monitor", s)
            let cs = colors(try await render(rt, s, systemData))
            #expect(!cs.isEmpty)
            #expect(Set(cs) == ["#112233"], "\(layout): \(Set(cs))")
        }
    }

    @Test func levelModeFollowsFill() async throws {
        let low = json(#"{"cpu":{"total":0.05},"ram":{"used":1e9,"total":16e9},"disk":{"free":4.9e11,"total":5e11},"network":null,"battery":{"level":0.95,"isCharging":false}}"#)
        let high = json(#"{"cpu":{"total":0.97},"ram":{"used":15.5e9,"total":16e9},"disk":{"free":1e10,"total":5e11},"network":null,"battery":{"level":0.05,"isCharging":false}}"#)
        for layout in ["bars", "rings"] {
            let s = settings("By fill level", layout)
            let rt = await load("system-monitor", s)
            let a = colors(try await render(rt, s, low)), b = colors(try await render(rt, s, high))
            #expect(a.count == b.count && !a.isEmpty)
            #expect(zip(a, b).allSatisfy { $0 != $1 }, "\(layout): \(a) vs \(b)")
            #expect(a.first?.hasPrefix("#4") == true && b.first?.hasPrefix("#FF") == true, "\(layout): \(a) vs \(b)")
        }
    }

    @Test func customModeUsesPerMetricColors() async throws {
        var s = settings("Custom per metric", "bars")
        s["cpuColor"] = .string("#010203"); s["ramColor"] = .string("#040506")
        let rt = await load("system-monitor", s)
        let cs = colors(try await render(rt, s, systemData))
        #expect(cs.starts(with: ["#010203", "#040506"]), "\(cs)")
    }
}
