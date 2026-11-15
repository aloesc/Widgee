import Testing
import SwiftUI
import Foundation
import WidgeeCore
@testable import Renderer

private let sample = """
{"type":"VStack","props":{"spacing":6,"padding":4},"children":[
 {"type":"HStack","children":[
   {"type":"Image","props":{"systemName":"laptopcomputer","color":"accent"}},
   {"type":"Spacer"},
   {"type":"Text","props":{"text":"78 %","size":28,"weight":"semibold","monospacedDigit":true}}]},
 {"type":"LinearBar","props":{"value":0.78}},
 {"type":"HStack","children":[
   {"type":"Ring","props":{"value":0.78,"color":"#30D158"},"children":[{"type":"Text","props":{"text":"78"}}]},
   {"type":"Gauge","props":{"value":0.4},"children":[{"type":"Text","props":{"text":"40"}}]}]},
 {"type":"SegmentedBar","props":{"value":0.5,"segments":8}},
 {"type":"Sparkline","props":{"values":[1,3,2,5,4],"fill":true}},
 {"type":"LineChart","props":{"values":[1,3,2,5,4],"area":true}},
 {"type":"BarChart","props":{"values":[1,3,2],"labels":["a","b","c"]}},
 {"type":"HStack","children":[
   {"type":"DigitalClock","props":{"timeZone":"Europe/Moscow","hour12":true}},
   {"type":"AnalogClock","props":{"timeZone":"Asia/Tokyo","hour12":false}}]},
 {"type":"ZStack","children":[{"type":"Text","props":{"text":"z"}}]}
]}
"""

/// UINode декодируется синтезированным Codable (все ключи обязательны),
/// поэтому в тестах дописываем пропущенные props/children.
private func normalize(_ v: JSONValue) -> JSONValue {
    guard case .object(var o) = v else { return v }
    if o["props"] == nil { o["props"] = .object([:]) }
    if case .array(let c)? = o["children"] { o["children"] = .array(c.map(normalize)) }
    else if o["children"] == nil { o["children"] = .array([]) }
    return .object(o)
}

private func decode(_ s: String) throws -> UINode {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))
    return try JSONDecoder().decode(UINode.self, from: JSONEncoder().encode(normalize(v)))
}

@Suite struct RendererTests {
    @MainActor @Test func buildsAllComponentsAtAllSizes() throws {
        let node = try decode(sample)
        for sc in SizeClass.allCases {
            let img = renderWidgetImage(node: node, sizeClass: sc, scale: 1)
            #expect(img != nil)
        }
    }

    @MainActor @Test func clockVariantPropsRender() throws {
        let node = try decode("""
        {"type":"VStack","children":[
         {"type":"AnalogClock","props":{"numbers":"none","ticks":true,"size":120}},
         {"type":"AnalogClock","props":{"numbers":"quarters","dots":true,"showSeconds":false}},
         {"type":"AnalogClock","props":{"numbers":"bogus","ticks":"x","dots":5}},
         {"type":"DigitalClock","props":{"part":"hour","monospaced":true,"weight":"heavy"}},
         {"type":"DigitalClock","props":{"part":"minute","hour12":true}}]}
        """)
        for sc in SizeClass.allCases { #expect(renderWidgetImage(node: node, sizeClass: sc, scale: 1) != nil) }
        let d = Date(timeIntervalSince1970: 1767261600)
        let utc = TimeZone(identifier: "UTC")!
        #expect(DigitalClockView.format(d, timeZone: utc, hour12: false, seconds: true, part: "hour") == "10")
        #expect(DigitalClockView.format(d, timeZone: utc, hour12: true, seconds: false, part: "minute") == "00")
        #expect(DigitalClockView.format(d, timeZone: utc, hour12: false, seconds: false) == "10:00")
    }

    @Test func allKnownTypesCovered() throws {
        let node = try decode(sample)
        var seen = Set<String>()
        func walk(_ n: UINode) { seen.insert(n.type); n.children.forEach(walk) }
        walk(node)
        #expect(seen == WidgetTreeView.knownTypes)
    }

    @MainActor @Test func badInputsDoNotCrash() throws {
        let bad = try decode("""
        {"type":"Bogus","props":{"x":1},"children":[
         {"type":"Ring","props":{"value":"abc","size":-5,"color":42}},
         {"type":"Sparkline","props":{"values":"no"}},
         {"type":"BarChart","props":{"values":[1,"x",null],"labels":5}},
         {"type":"AnalogClock","props":{"timeZone":"Nope/Zone"}},
         {"type":"Text","props":{"text":5,"size":1e99}},
         {"type":"SegmentedBar","props":{"segments":-3,"value":9}}]}
        """)
        #expect(renderWidgetImage(node: bad, scale: 1) != nil)
    }

    @MainActor @Test func deepRecursionIsLimited() {
        var n = UINode(type: "Text", props: ["text": .string("deep")])
        for _ in 0..<500 { n = UINode(type: "VStack", children: [n]) }
        #expect(renderWidgetImage(node: n, scale: 1) != nil)
    }

    @Test func clampsBarValues() {
        #expect(Props(["value": .number(1.7)]).unit() == 1)
        #expect(Props(["value": .number(-3)]).unit() == 0)
        #expect(Props(["value": .number(0.4)]).unit() == 0.4)
        #expect(Props(["value": .string("x")]).unit() == 0)
        #expect(Props([:]).unit() == 0)
        #expect(Props.clamp01(.nan) == 0)
    }

    @Test func colorResolution() {
        let ctx = RenderContext(theme: Theme(accentHex: "#FF0000"), sizeClass: .medium)
        #expect(ctx.color("accent") == Color(hex: "#FF0000"))
        #expect(ctx.color("#00FF00") == Color(hex: "#00FF00"))
        #expect(ctx.color("primary") == .primary)
        #expect(ctx.color("secondary") == .secondary)
        #expect(ctx.color("garbage") == .primary)
    }

    @Test func clockAngles() {
        let tz = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 3 * 3600 + 30 * 60 + 15) // 03:30:15 UTC
        let a = ClockAngles.at(d, timeZone: tz, hour12: true)
        #expect(abs(a.hour - 105.125) < 1e-6)
        #expect(abs(a.minute - 181.5) < 1e-6)
        #expect(abs(a.second - 90) < 1e-6)
        #expect(abs(ClockAngles.at(d, timeZone: tz, hour12: false).hour - 52.5625) < 1e-6)
        let tokyo = ClockAngles.at(d, timeZone: TimeZone(identifier: "Asia/Tokyo")!, hour12: true) // 12:30:15
        #expect(abs(tokyo.hour - 15.125) < 1e-6)
    }

    @Test func digitalFormat() {
        let d = Date(timeIntervalSince1970: 15 * 3600 + 5 * 60)
        let utc = TimeZone(identifier: "UTC")!
        #expect(DigitalClockView.format(d, timeZone: utc, hour12: false, seconds: false) == "15:05")
        #expect(DigitalClockView.format(d, timeZone: utc, hour12: true, seconds: true) == "3:05:00 PM")
    }

    @MainActor @Test func rendersPNG() throws {
        let node = try decode(sample)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widgee-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("w.png")
        #expect(renderWidgetPNG(node: node, to: url, sizeClass: .large))
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 0)
    }
}

@Suite("Fonts") struct FontTests {
    @Test func themeWithoutFontFamilyRoundTrips() throws {
        let old = ##"{"cornerRadius":22,"fontDesign":"serif","accentHex":"#0A84FF","isDark":false}"##
        let t = try JSONDecoder().decode(Theme.self, from: Data(old.utf8))
        #expect(t.fontFamily == nil && t.fontDesign == .serif)
        let enc = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        #expect(!enc.contains("fontFamily"))
        var t2 = t; t2.fontFamily = "Menlo"
        #expect(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(t2)).fontFamily == "Menlo")
    }

    @Test func knownAndUnknownFamilies() {
        #expect(FontResolver.postScriptName(family: "Menlo", weight: .bold)?.contains("Menlo") == true)
        #expect(FontResolver.postScriptName(family: "Helvetica Neue", weight: .regular) != nil)
        #expect(FontResolver.postScriptName(family: "No Such Font Xyz", weight: .regular) == nil)
        for fam in ["Menlo", "No Such Font Xyz", nil] {
            for d in FontDesign.allCases {
                let ctx = RenderContext(theme: Theme(fontDesign: d, fontFamily: fam), sizeClass: .medium)
                _ = ctx.font(size: 14, weight: .semibold)
            }
        }
    }

    // MARK: text fit / textScale

    /// Ширина «чернил» (непрозрачных пикселей) отрендеренного дерева в окне 500x100.
    @MainActor private func inkWidth(_ json: String, textScale: Double? = nil, fontWeight: String? = nil, family: String? = nil) throws -> Int {
        try ink(json, textScale: textScale, fontWeight: fontWeight, family: family).width
    }

    @MainActor private func ink(_ json: String, textScale: Double? = nil, fontWeight: String? = nil, family: String? = nil) throws -> (width: Int, area: Int) {
        let node = try decode(json)
        let view = WidgetTreeView(node: node, theme: Theme(fontFamily: family, textScale: textScale, fontWeight: fontWeight))
            .frame(width: 500, height: 100, alignment: .leading)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let cg = r.cgImage else { return (0, 0) }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, area = 0
        for y in 0..<h { for x in 0..<w { let a = Int(buf[(y * w + x) * 4 + 3]); if a > 40 { minX = min(minX, x); maxX = max(maxX, x) }; area += a } }
        return (maxX < 0 ? 0 : maxX - minX + 1, area)
    }

    private func fitText(_ w: Int, _ h: Int, text: String = "12:34") -> String {
        ##"{"type":"Text","props":{"text":"\##(text)","fit":true,"width":\##(w),"height":\##(h),"color":"#000000","align":"leading"}}"##
    }

    @MainActor @Test func textFitRendersWithoutCrash() throws {
        for j in [
            #"{"type":"Text","props":{"text":"x","fit":true}}"#,
            #"{"type":"Text","props":{"text":"x","fit":true,"width":100}}"#,
            fitText(2, 40), fitText(100, 30, text: ""), fitText(0, 0),
            #"{"type":"DigitalClock","props":{"fit":true,"width":200,"height":60,"align":"trailing"}}"#,
            #"{"type":"DigitalClock","props":{"fit":true}}"#,
        ] { _ = try inkWidth(j) }
    }

    @MainActor @Test func textFitGrowsWithBox() throws {
        let a = try inkWidth(fitText(200, 60))
        let b = try inkWidth(fitText(400, 60))
        #expect(a > 0)
        #expect(b >= a)
        #expect(a <= 200 && b <= 400)
    }

    @MainActor @Test func textScaleScalesPlainAndFitText() throws {
        let plain = ##"{"type":"Text","props":{"text":"Hello","size":20,"color":"#000000"}}"##
        let s1 = try inkWidth(plain, textScale: 1)
        let s2 = try inkWidth(plain, textScale: 2)
        #expect(s2 > s1 && s1 > 0)
        // fit работает и при ручном масштабе: 100 % совпадает с Auto, 50 % вдвое мельче, выше 100 % коробка не даёт расти.
        let auto = try inkWidth(fitText(400, 60))
        let full = try inkWidth(fitText(400, 60), textScale: 1)
        let half = try inkWidth(fitText(400, 60), textScale: 0.5)
        let big = try inkWidth(fitText(400, 60), textScale: 3)
        #expect(abs(full - auto) <= max(3, auto / 20))
        #expect(abs(half * 2 - auto) <= max(4, auto / 10))
        #expect(big <= 400 && abs(big - auto) <= max(3, auto / 20))
    }

    @MainActor @Test func fontWeightOverridesTextWeight() throws {
        let t = ##"{"type":"Text","props":{"text":"Hamburgefons","size":30,"weight":"bold","color":"#000000"}}"##
        let auto = try ink(t).area
        let thin = try ink(t, fontWeight: "thin").area
        let black = try ink(t, fontWeight: "black").area
        #expect(thin < auto && auto < black)
        #expect(try ink(t, fontWeight: "bogus").area == auto)
    }

    @MainActor @Test func fontWeightOverridesDigitalClock() throws {
        for mono in ["false", "true"] {
            let j = ##"{"type":"DigitalClock","props":{"timeZone":"UTC","size":30,"monospaced":\##(mono),"color":"#000000"}}"##
            let thin = try ink(j, fontWeight: "thin").area
            let black = try ink(j, fontWeight: "black").area
            #expect(thin < black, "monospaced=\(mono)")
        }
    }

    @MainActor @Test func fontWeightSafeOnSparseFamilies() throws {
        let t = ##"{"type":"Text","props":{"text":"Hello","size":24,"color":"#000000"}}"##
        for fam in ["Menlo", "Marker Felt", "Georgia", "NoSuchFont"] {
            for w in ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"] {
                #expect(try ink(t, fontWeight: w, family: fam).width > 0, "\(fam) \(w)")
            }
        }
    }
}
