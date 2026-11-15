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
