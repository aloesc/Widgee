import SwiftUI
import WidgeeCore

/// Применяет `WidgetBackgroundStyle` к контенту. Реализации можно подменять
/// (например, fallback на материалы для старых систем).
public protocol BackgroundRenderer: Sendable {
    @MainActor
    func apply(to content: AnyView, style: WidgetBackgroundStyle, cornerRadius: CGFloat) -> AnyView
}

extension View {
    /// Рисует фон виджета по `style` со скруглением `cornerRadius`.
    @MainActor
    public func widgetBackground(_ style: WidgetBackgroundStyle,
                                 cornerRadius: CGFloat,
                                 renderer: any BackgroundRenderer = LiquidGlassBackgroundRenderer()) -> some View {
        renderer.apply(to: AnyView(self), style: style, cornerRadius: cornerRadius)
    }
}
