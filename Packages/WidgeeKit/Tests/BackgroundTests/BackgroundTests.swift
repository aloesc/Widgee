import Testing
import SwiftUI
import WidgeeCore
@testable import Background

@Suite struct HexColorTests {
    @Test func parsesShortAndLong() {
        #expect(HexColor(hex: "#F00") == HexColor(red: 1, green: 0, blue: 0))
        #expect(HexColor(hex: "00ff00") == HexColor(red: 0, green: 1, blue: 0))
        let c = HexColor(hex: "#0000FF80")
        #expect(c?.blue == 1)
        #expect(abs((c?.alpha ?? 0) - 128.0 / 255) < 1e-9)
    }

    @Test func rejectsInvalid() {
        for s in ["", "#", "#12", "#12345", "#GGGGGG", "#1234567", "#ff00ff00ff", "red", "#ёёё"] {
            #expect(HexColor(hex: s) == nil, "\(s)")
        }
    }
}

@Suite struct BackgroundRendererTests {
    @MainActor @Test func allStylesBuild() {
        let styles: [WidgetBackgroundStyle] = [
            .liquidGlass, .clear, .color(hex: "#112233", opacity: 0.5),
            .tint(hex: "#0A84FF", opacity: 0.3), .color(hex: "bad", opacity: 2), .tint(hex: "bad", opacity: 1),
        ]
        for s in styles {
            _ = Text("x").widgetBackground(s, cornerRadius: 22)
            _ = Text("x").widgetBackground(s, cornerRadius: -5)
        }
    }
}
