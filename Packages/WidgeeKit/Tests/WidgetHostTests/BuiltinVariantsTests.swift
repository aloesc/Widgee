import Testing
import Foundation
import WidgeeCore
@testable import WidgetHost

private let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/BuiltinWidgets")

private func json(_ s: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
}

private typealias Sz = (name: String, w: Double, h: Double, cls: SizeClass)
private let allSizes: [Sz] = [("S", 170, 170, .small), ("M", 360, 170, .medium),
                              ("L", 360, 360, .large), ("XL", 720, 380, .extraLarge)]

private func cellSize(_ s: String) -> Sz {
    switch s {
    case "1x1", "S": return allSizes[0]
    case "2x1", "M": return allSizes[1]
    case "2x2", "L": return allSizes[2]
    default: return allSizes[3]
    }
}

private func data(_ id: String, empty: Bool) -> JSONValue {
    switch (id, empty) {
    case ("clock", true): return json(#"{"now":null}"#)
    case ("clock", false): return json(#"{"now":{"now":1767261600000}}"#)
    case ("system-monitor", true): return json(#"{"cpu":null,"ram":null,"disk":null,"network":null,"battery":null}"#)
    case ("system-monitor", false):
        return json(#"""
        {"cpu":{"total":0.42,"perCore":[0.1,0.9,0.5,0.3,0.2,0.7,0.4,0.6,0.1,0.2,0.8,0.3]},"ram":{"used":8e9,"total":16e9},
         "disk":{"free":2e11,"total":5e11},"network":{"downBytesPerSec":12345,"upBytesPerSec":2345},
         "battery":{"level":0.8,"isCharging":true}}
        """#)
    case (_, true): return json(#"{"w":null}"#)
    default:
        return json(#"""
        {"w":{"stale":false,"value":{"current":{"time":"2026-01-01T10:00","temperature_2m":3.4,"weather_code":2,"is_day":1},
         "hourly":{"time":["2026-01-01T10:00","2026-01-01T11:00","2026-01-01T12:00","2026-01-01T13:00","2026-01-01T14:00","2026-01-01T15:00",
          "2026-01-01T16:00","2026-01-01T17:00","2026-01-01T18:00","2026-01-01T19:00","2026-01-01T20:00","2026-01-01T21:00"],
          "temperature_2m":[3,4,5,5,4,3,2,2,1,1,0,0],"weather_code":[2,2,3,3,61,61,0,0,1,1,2,2]},
         "daily":{"time":["2026-01-01","2026-01-02","2026-01-03","2026-01-04","2026-01-05"],"weather_code":[2,3,61,0,1],
          "temperature_2m_max":[5,6,4,7,8],"temperature_2m_min":[-1,0,1,2,3]}}}}
        """#)
    }
}

private func manifest(_ id: String) throws -> WidgetManifest {
    try WidgetManifest.parse(Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("manifest.json")))
}

private func allNodes(_ n: UINode) -> [UINode] { [n] + n.children.flatMap(allNodes) }

@Suite struct BuiltinVariantsTests {
    static let ids = ["clock", "weather", "system-monitor"]

    @Test func variantSettingsAreValid() throws {
        for id in Self.ids {
            let m = try manifest(id)
            #expect(m.variants.count >= 4, "\(id)")
            for v in m.variants {
                #expect(m.sizes.contains(v.size), "\(id)/\(v.key) size \(v.size)")
                for (k, val) in v.settings {
                    guard let f = m.settings.first(where: { $0.key == k }) else {
                        Issue.record("\(id)/\(v.key): undeclared setting \(k)"); continue
                    }
                    if f.type == "select", let opts = f.options, case .string(let s) = val {
                        #expect(opts.contains(s), "\(id)/\(v.key): \(k)=\(s) not in options")
                    }
                }
            }
        }
    }

    @Test func everyVariantRendersAtOwnSizeAndAllSizes() async throws {
        for id in Self.ids {
            let m = try manifest(id)
            for v in m.variants {
                let rt = await WidgetRuntime.load(directory: root.appendingPathComponent(id), settings: v.settings,
                                                  renderTimeout: 5, loadTimeout: 5)
                #expect(rt.state == .loaded, "\(id)/\(v.key): \(rt.state)")
                var sizes = allSizes
                sizes.append(cellSize(v.size))
                for a in ContentAlignment.allCases {
                    for sz in sizes {
                        for empty in [false, true] {
                            let ctx = RenderContext(size: .init(width: sz.w, height: sz.h, sizeClass: sz.cls),
                                                    theme: Theme(alignment: a), settings: v.settings,
                                                    data: data(id, empty: empty))
                            let tree = try await rt.render(ctx)
                            #expect(!tree.type.isEmpty, "\(id)/\(v.key) \(a) \(sz.name) empty=\(empty)")
                            #expect(!allNodes(tree).contains { $0.type == "?" }, "\(id)/\(v.key) placeholder")
                        }
                    }
                }
            }
        }
    }

    @Test func newClockStylesUseAnalogProps() async throws {
        let want: [String: String] = ["analog-minimal": "ticks", "analog-dots": "dots", "analog-seconds": "ticks"]
        for (style, prop) in want {
            let s: [String: JSONValue] = ["style": .string(style)]
            let rt = await WidgetRuntime.load(directory: root.appendingPathComponent("clock"), settings: s,
                                              renderTimeout: 5, loadTimeout: 5)
            let ctx = RenderContext(size: .init(width: 170, height: 170, sizeClass: .small), theme: Theme(),
                                    settings: s, data: data("clock", empty: false))
            let tree = try await rt.render(ctx)
            let clock = allNodes(tree).first { $0.type == "AnalogClock" }
            #expect(clock?.props[prop] == .bool(true), "\(style)")
        }
    }

    @Test func coresLayoutRendersOneBarPerCore() async throws {
        let s: [String: JSONValue] = ["layout": .string("cores")]
        let rt = await WidgetRuntime.load(directory: root.appendingPathComponent("system-monitor"), settings: s,
                                          renderTimeout: 5, loadTimeout: 5)
        let ctx = RenderContext(size: .init(width: 360, height: 360, sizeClass: .large), theme: Theme(),
                                settings: s, data: data("system-monitor", empty: false))
        let tree = try await rt.render(ctx)
        #expect(allNodes(tree).filter { $0.type == "LinearBar" }.count == 12)
    }
}
