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
