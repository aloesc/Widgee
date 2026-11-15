import Foundation
import Testing
@testable import WidgetHost
import WidgeeCore

@Suite struct ManifestSizeTests {
    private func manifest(sizes: String) -> Data {
        Data("""
        {"id":"w","name":"W","version":"1.0.0","author":"a","sdk":"\(WidgeeCore.sdkVersion)","sizes":\(sizes)}
        """.utf8)
    }

    @Test func cellSizesAreNormalizedToLegacyNames() throws {
        let m = try WidgetManifest.parse(manifest(sizes: #"["1x1","2×1","2x2","4x2"]"#))
        #expect(m.sizes == ["S", "M", "L", "XL"])
    }

    @Test func legacySizeNamesStillWork() throws {
        let m = try WidgetManifest.parse(manifest(sizes: #"["S","XL"]"#))
        #expect(m.sizes == ["S", "XL"])
    }

    @Test func unknownCellSizeIsRejected() {
        #expect(throws: WidgetManifestError.self) { try WidgetManifest.parse(manifest(sizes: #"["3x3"]"#)) }
    }
}
