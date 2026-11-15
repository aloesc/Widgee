import Foundation
import Testing
@testable import WidgeeCore

@Test func smoke() { #expect(true) }

@Test func uiNodeDecodesWithoutOptionalKeys() throws {
    let node = try JSONDecoder().decode(UINode.self, from: Data(#"{"type":"Spacer"}"#.utf8))
    #expect(node.type == "Spacer" && node.props.isEmpty && node.children.isEmpty)
}

@Test func themeAlignmentRoundTripsAndDefaultsToAuto() throws {
    #expect(Theme().alignment == .auto)
    for a in ContentAlignment.allCases {
        let data = try JSONEncoder().encode(Theme(alignment: a))
        #expect(String(decoding: data, as: UTF8.self).contains("\"alignment\":\"\(a.rawValue)\""))
        #expect(try JSONDecoder().decode(Theme.self, from: data).alignment == a)
    }
    let old = ##"{"cornerRadius":22,"fontDesign":"standard","accentHex":"#0A84FF","isDark":true}"##
    let t = try JSONDecoder().decode(Theme.self, from: Data(old.utf8))
    #expect(t.alignment == .auto && t.isDark)
}

@Test func themeTextScaleCodec() throws {
    let old = ##"{"cornerRadius":22,"fontDesign":"standard","accentHex":"#0A84FF","isDark":false}"##
    #expect(try JSONDecoder().decode(Theme.self, from: Data(old.utf8)).textScale == nil)
    let enc = try JSONEncoder().encode(Theme())
    #expect(!String(decoding: enc, as: UTF8.self).contains("textScale"))
    let t = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(Theme(textScale: 1.5)))
    #expect(t.textScale == 1.5)
}

@Suite struct ThemeFontWeightTests {
    @Test func oldJSONWithoutFieldDecodes() throws {
        let j = ##"{"cornerRadius":22,"fontDesign":"standard","accentHex":"#0A84FF","isDark":false}"##
        let t = try JSONDecoder().decode(Theme.self, from: Data(j.utf8))
        #expect(t.fontWeight == nil)
        #expect(!String(decoding: try JSONEncoder().encode(t), as: UTF8.self).contains("fontWeight"))
    }
    @Test func roundTrip() throws {
        let t = Theme(fontWeight: "thin")
        #expect(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(t)).fontWeight == "thin")
    }
    @Test func unknownValueDecodesAsString() throws {
        let j = ##"{"cornerRadius":22,"fontDesign":"standard","accentHex":"#0A84FF","isDark":false,"fontWeight":"wat"}"##
        #expect(try JSONDecoder().decode(Theme.self, from: Data(j.utf8)).fontWeight == "wat")
    }
}
