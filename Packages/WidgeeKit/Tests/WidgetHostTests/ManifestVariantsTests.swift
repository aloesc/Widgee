import Foundation
import Testing
@testable import WidgetHost
import WidgeeCore

@Suite struct ManifestVariantsTests {
    private func manifest(variants: String, sizes: String = #"["1x1","2x1","2x2"]"#) -> Data {
        Data("""
        {"id":"w","name":"W","version":"1.0.0","author":"a","sdk":"\(WidgeeCore.sdkVersion)","sizes":\(sizes),
         "settings":[{"key":"style","type":"select","label":"Style","default":"a","options":["a","b"]}],
         "variants":\(variants)}
        """.utf8)
    }

    @Test func variantsAreParsedAndSizesNormalized() throws {
        let m = try WidgetManifest.parse(manifest(variants: #"[{"key":"a","name":"A","size":"2x1","settings":{"style":"b"}},{"key":"b","name":"B","size":"1x1"}]"#))
        #expect(m.variants.map(\.key) == ["a", "b"])
        #expect(m.variants[0].size == "M" && m.variants[1].size == "S")
        #expect(m.variants[0].settings["style"] == .string("b"))
    }

    @Test func manifestWithoutVariantsHasEmptyList() throws {
        let m = try WidgetManifest.parse(manifest(variants: "[]"))
        #expect(m.variants.isEmpty)
    }

    @Test(arguments: [
        #"[{"key":"a","name":"A","size":"2x1"},{"key":"a","name":"B","size":"2x1"}]"#,   // дубликат ключа
        #"[{"key":"","name":"A","size":"2x1"}]"#,                                          // пустой ключ
        #"[{"key":"a/b","name":"A","size":"2x1"}]"#,                                       // «/» в ключе
        #"[{"key":"a","name":" ","size":"2x1"}]"#,                                         // пустое имя
        #"[{"key":"a","name":"A","size":"4x2"}]"#,                                         // размер вне sizes
        #"[{"key":"a","name":"A","size":"2x1","settings":{"nope":"x"}}]"#,                // неизвестная настройка
    ])
    func invalidVariantsAreRejected(_ variants: String) {
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(manifest(variants: variants)) }
    }
}
