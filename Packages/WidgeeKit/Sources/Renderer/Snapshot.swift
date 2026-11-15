import SwiftUI
import AppKit
import WidgeeCore
import Background

extension SizeClass {
    /// Типовой размер виджета в pt.
    public var defaultSize: CGSize {
        switch self {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 338, height: 158)
        case .large: CGSize(width: 338, height: 354)
        case .extraLarge: CGSize(width: 715, height: 354)
        }
    }
}

/// Рендерит дерево (на стеклянном фоне) в NSImage. `nil`, если рендер не удался.
@MainActor
public func renderWidgetImage(node: UINode, theme: Theme = Theme(), sizeClass: SizeClass = .medium,
                              background: WidgetBackgroundStyle = .color(hex: "#FFFFFF", opacity: 0.9),
                              size: CGSize? = nil, scale: CGFloat = 2) -> NSImage? {
    let s = size ?? sizeClass.defaultSize
    let view = WidgetTreeView(node: node, theme: theme, sizeClass: sizeClass)
        .padding(14)
        .frame(width: s.width, height: s.height)
        .widgetBackground(background, cornerRadius: theme.cornerRadius)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    let r = ImageRenderer(content: view)
    r.scale = scale
    return r.nsImage
}

/// Рендерит дерево и пишет PNG. Возвращает `false` при ошибке.
@MainActor
@discardableResult
public func renderWidgetPNG(node: UINode, to url: URL, theme: Theme = Theme(),
                            sizeClass: SizeClass = .medium,
                            background: WidgetBackgroundStyle = .color(hex: "#FFFFFF", opacity: 0.9)) -> Bool {
    guard let img = renderWidgetImage(node: node, theme: theme, sizeClass: sizeClass, background: background),
          let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    do { try png.write(to: url); return true } catch { return false }
}
