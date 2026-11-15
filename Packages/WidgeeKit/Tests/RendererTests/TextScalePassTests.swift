import Testing
import SwiftUI
import AppKit
import Foundation
import WidgeeCore
import WidgetHost
@testable import Renderer

private func node(_ s: String) throws -> UINode { try JSONDecoder().decode(UINode.self, from: Data(s.utf8)) }

private func fit(_ text: String, _ w: Int, _ h: Int) -> String {
    ##"{"type":"Text","props":{"text":"\##(text)","fit":true,"width":\##(w),"height":\##(h),"lineLimit":1}}"##
}

/// Стек как у погоды compact: подпись, ряд «иконка + главное значение», подпись.
private func labelled(_ main: String, mainWidth: Int = 80) -> String {
    ##"{"type":"VStack","props":{"spacing":4,"width":170,"height":170,"padding":14},"children":[\##(fit("Yekaterinburg", 142, 34)),"##
        + ##"{"type":"HStack","children":[{"type":"Image","props":{"systemName":"cloud.fill","size":40}},\##(fit(main, mainWidth, 74))]},"##
        + ##"\##(fit("Overcast", 142, 34))]}"##
}

private func allNodes(_ n: UINode) -> [UINode] { [n] + n.children.flatMap(allNodes) }

@MainActor private func boxHeights(_ n: UINode) -> [String: CGFloat] {
    var out: [String: CGFloat] = [:]
    for c in allNodes(n) { if let b = TextScalePass.fitBox(c) { out[c.props["text"]?.stringValue ?? ""] = b.height } }
    return out
}

@MainActor private func boxBudget(_ n: UINode) -> CGFloat {
    allNodes(n).compactMap { TextScalePass.fitBox($0)?.height }.reduce(0, +)
}

@MainActor @Suite struct TextScalePassTests {
    @Test func autoAndShrinkKeepTheTree() throws {
        let n = try node(labelled("4°"))
        let auto = TextScalePass.run(n, theme: Theme())
        #expect(auto.node == n && auto.plain == 1 && auto.fit == 1)
        let half = TextScalePass.run(n, theme: Theme(textScale: 0.5))
        #expect(half.node == n && half.plain == 0.5 && half.fit == 0.5)
    }

    @Test func primaryBoxGrowsAtTheExpenseOfLabels() throws {
        let n = try node(labelled("4°"))
        let before = boxHeights(n)
        var last: CGFloat = 74
        for scale in [1.2, 1.5, 2, 3] {
            let r = TextScalePass.run(n, theme: Theme(textScale: scale))
            let after = boxHeights(r.node)
            let main = try #require(after["4°"])
            #expect(main > 74 && main >= last, "scale \(scale)")
            #expect(after.values.reduce(0, +) <= before.values.reduce(0, +) + 0.01, "scale \(scale): boxes overflow")
            #expect(r.fit == 1)
            last = main
        }
    }

    @Test func tinyLabelsAreDropped() throws {
        // Узкая строка в широкой коробке может занять всю высоту: подписи исчезают.
        let r = TextScalePass.run(try node(labelled("4", mainWidth: 142)), theme: Theme(textScale: 3))
        let after = boxHeights(r.node)
        #expect(after["Yekaterinburg"] == nil && after["Overcast"] == nil)
        #expect(try #require(after["4"]) > 130)
    }

    @Test func widthLimitedPrimaryIsLeftAlone() throws {
        let n = try node(labelled("23:37:05 PM"))
        #expect(TextScalePass.run(n, theme: Theme(textScale: 3)).node == n)
    }

    @Test func equalPrimaryRowsGrowTogether() throws {
        // Часы над минутами и дата под ними: обе главные строки растут одинаково, дата уступает.
        let n = try node(##"{"type":"VStack","props":{"height":142},"children":[\##(fit("00", 142, 54)),\##(fit("04", 142, 54)),\##(fit("Saturday", 142, 34))]}"##)
        let after = boxHeights(TextScalePass.run(n, theme: Theme(textScale: 3)).node)
        let h = try #require(after["00"])
        #expect(h > 54 && after["04"] == h)
        #expect((after["Saturday"] ?? 0) < 34)
    }

    @Test func sliderKeepsWorkingUpToThreeHundredPercent() throws {
        let n = try node(labelled("4°"))
        let h = try [1.5, 2, 2.5, 3].map { try #require(boxHeights(TextScalePass.run(n, theme: Theme(textScale: $0)).node)["4°"]) }
        #expect(h[0] < h[1] && h[1] < h[2] && h[2] < h[3])
    }

    @Test func equalRowsAreLeftAlone() throws {
        let n = try node(##"{"type":"VStack","props":{"height":120},"children":[\##(fit("a", 100, 40)),\##(fit("b", 100, 40)),\##(fit("c", 100, 36))]}"##)
        #expect(TextScalePass.run(n, theme: Theme(textScale: 3)).node == n)
    }

    @Test func heavierWeightLeavesLessRoomToGrow() throws {
        let n = try node(labelled("-14°", mainWidth: 142))
        let thin = try #require(boxHeights(TextScalePass.run(n, theme: Theme(textScale: 3, fontWeight: "ultraLight")).node)["-14°"])
        let black = try #require(boxHeights(TextScalePass.run(n, theme: Theme(textScale: 3, fontWeight: "black")).node)["-14°"])
        #expect(thin > black)
    }

    @Test func textInAFixedColumnDoesNotOutgrowIt() throws {
        // Без lineLimit строка в колонке не сжимается, а переносится: расти шире колонки ей нельзя.
        let cell = ##"{"type":"Text","props":{"text":"12°","size":13,"width":40}}"##
        let c = TextScalePass.run(try node(##"{"type":"HStack","children":[\##(cell)]}"##), theme: Theme(textScale: 3)).plain
        #expect(c > 1 && c < 2.5)
    }

    @Test func percentAboveThreeHundredIsLiteralWhenThereIsRoom() {
        #expect(TextScalePass.eased(4, limit: 10) == 4)
        #expect(TextScalePass.eased(4, limit: 3.9) == 3.9)
        #expect(TextScalePass.eased(2, limit: 10) == 2)
        #expect(TextScalePass.eased(2, limit: 1.4) == 1.2)
    }

    @Test func plainTextStopsAtTheContainer() throws {
        let row = ##"{"type":"Text","props":{"text":"CPU 42 %","size":20,"lineLimit":1}}"##
        let boxed = try node(##"{"type":"VStack","props":{"spacing":8,"height":100},"children":[\##(row),\##(row),\##(row)]}"##)
        let c = TextScalePass.run(boxed, theme: Theme(textScale: 3)).plain
        #expect(c > 1 && c < 1.5)
        let mid = TextScalePass.run(boxed, theme: Theme(textScale: 2)).plain
        #expect(mid > 1 && mid < c)
        let free = try node(##"{"type":"VStack","props":{"spacing":8},"children":[\##(row),\##(row),\##(row)]}"##)
        #expect(TextScalePass.run(free, theme: Theme(textScale: 3)).plain == 3)
    }
}

// MARK: встроенные виджеты

private let builtinRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/BuiltinWidgets")

private let builtinIDs: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: builtinRoot.path)) ?? [])
    .filter { FileManager.default.fileExists(atPath: builtinRoot.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }
    .sorted()

private let builtinSizes: [(String, Double, Double, SizeClass)] = [
    ("S", 170, 170, .small), ("M", 360, 170, .medium), ("L", 360, 360, .large),
]

private let builtinData: JSONValue = (try? JSONDecoder().decode(JSONValue.self, from: Data(#"""
{"battery":{"level":0.8,"isCharging":true,"isPluggedIn":true},"disk":{"free":2e11,"total":5e11},
 "network":{"downBytesPerSec":2345678,"upBytesPerSec":12345},"now":{"now":1788000000000,"tick":1},
 "cpu":{"usage":0.42,"perCore":[0.2,0.6,0.4,0.8]},"memory":{"used":8e9,"total":16e9,"usage":0.5},
 "w":{"value":{"current":{"temperature_2m":4,"weather_code":3,"is_day":1}}}}
"""#.utf8))) ?? .null

@MainActor @Suite struct BuiltinTextScaleTests {
    /// Ручной масштаб не раздувает коробки и не превышает запрошенный процент ни в одном встроенном виджете.
    /// С `WIDGEE_DUMP=<папка>` дополнительно пишет PNG каждого варианта для просмотра глазами
    /// (`WIDGEE_DUMP_FAMILY`, `WIDGEE_DUMP_WEIGHT` задают шрифт и вес).
    @Test(arguments: builtinIDs)
    func manualScaleKeepsTheBudget(_ id: String) async throws {
        let dir = builtinRoot.appendingPathComponent(id)
        let m = try WidgetManifest.parse(Data(contentsOf: dir.appendingPathComponent("manifest.json")))
        var defaults: [String: JSONValue] = [:]
        for f in m.settings { if let d = f.default { defaults[f.key] = d } }
        var configs: [(String, [String: JSONValue])] = [("default", defaults)]
        for v in m.variants { configs.append((v.key, defaults.merging(v.settings) { _, new in new })) }
        let env = ProcessInfo.processInfo.environment
        let dump = env["WIDGEE_DUMP"]
        for (name, settings) in configs {
            let rt = await WidgetRuntime.load(directory: dir, settings: settings, renderTimeout: 5, loadTimeout: 5)
            for sz in builtinSizes {
                let size = HostRenderContext.Size(width: sz.1, height: sz.2, sizeClass: sz.3)
                let tree = try await rt.render(HostRenderContext(size: size, theme: Theme(), settings: settings, data: builtinData))
                let budget = boxBudget(tree)
                for scale: Double? in [nil, 0.5, 1, 1.5, 2, 3] {
                    let theme = Theme(fontDesign: .rounded, isDark: true, fontFamily: env["WIDGEE_DUMP_FAMILY"], textScale: scale,
                                      fontWeight: env["WIDGEE_DUMP_WEIGHT"])
                    let r = TextScalePass.run(tree, theme: theme)
                    let tag = "\(id)/\(name) \(sz.0) x\(scale ?? 0)"
                    #expect(boxBudget(r.node) <= budget + 0.5, "\(tag): fit boxes grew")
                    let m = scale ?? 1
                    #expect(r.plain >= min(1, m) - 0.001 && r.plain <= m + 0.001, "\(tag): plain \(r.plain)")
                    guard let dump else { continue }
                    let view = WidgetTreeView(node: tree, theme: theme, sizeClass: sz.3)
                        .frame(width: sz.1, height: sz.2).clipped().background(Color(white: 0.12)).environment(\.colorScheme, .dark)
                    let ir = ImageRenderer(content: view)
                    ir.scale = 1
                    guard let tiff = ir.nsImage?.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                    try png.write(to: URL(fileURLWithPath: dump).appendingPathComponent("\(id)_\(name)_\(sz.0)_\(Int((scale ?? 0) * 100)).png"))
                }
            }
        }
    }
}
