import SwiftUI
import WidgeeCore

/// Единственное место с API macOS 26 (glassEffect).
public struct LiquidGlassBackgroundRenderer: BackgroundRenderer {
    public init() {}

    /// Доля непрозрачности цвета, которая идёт в заливку под стеклом.
    private let washStrength = 0.55

    @MainActor
    public func apply(to content: AnyView, style: WidgetBackgroundStyle, cornerRadius: CGFloat) -> AnyView {
        let radius = max(0, cornerRadius.isFinite ? cornerRadius : 0)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch style {
        case .liquidGlass:
            return AnyView(content.glassEffect(.regular, in: shape))
        case .clear:
            return AnyView(content)
        case .color(let hex, let opacity):
            let color = Color(hex: hex, opacity: opacity) ?? .clear
            return AnyView(content.background(color, in: shape))
        case .tint(let hex, let opacity):
            guard let color = Color(hex: hex, opacity: opacity) else {
                return AnyView(content.glassEffect(.regular, in: shape))
            }
            // Системный tint у glassEffect едва заметен, поэтому поверх стекла добавляем цветную заливку.
            let wash = Color(hex: hex, opacity: min(1, max(0, opacity)) * washStrength) ?? .clear
            return AnyView(
                content
                    .background(wash, in: shape)
                    .glassEffect(.regular.tint(color), in: shape)
            )
        }
    }
}
