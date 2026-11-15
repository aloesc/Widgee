import AppKit
import SwiftUI
import WidgeeCore

/// Реальные метрики текста (AppKit) для шрифта и веса из темы.
/// Нужны ручному «Text size»: размеры считаются по настоящему шрифту, а не по оценке «0.6 em на символ».
@MainActor
final class TextMetrics {
    let theme: Theme
    // Ширина строки и высота линии линейны по кеглю: меряем один раз на `probe` pt и масштабируем.
    private static let probe: CGFloat = 100
    private var widths: [String: CGFloat] = [:]
    private var lineHeights: [String: CGFloat] = [:]

    init(theme: Theme) { self.theme = theme }

    /// Тот же выбор шрифта, что в `RenderContext.font`: семейство из темы, иначе системный с `fontDesign`.
    func nsFont(size: CGFloat, weight own: Font.Weight, monospaced: Bool = false, monospacedDigit: Bool = false) -> NSFont {
        let weight = parseWeightStrict(theme.fontWeight) ?? own
        if !monospaced, let family = theme.fontFamily, !family.isEmpty,
           let name = FontResolver.postScriptName(family: family, weight: weight), let f = NSFont(name: name, size: size) {
            return f
        }
        let w = Self.nsWeight(weight)
        let base = monospacedDigit ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: w) : NSFont.systemFont(ofSize: size, weight: w)
        let design: NSFontDescriptor.SystemDesign? = monospaced ? .monospaced : {
            switch theme.fontDesign {
            case .standard: nil
            case .rounded: .rounded
            case .monospaced: .monospaced
            case .serif: .serif
            }
        }()
        guard let design, let d = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }

    func width(_ text: String, size: CGFloat, weight: Font.Weight, monospaced: Bool = false, monospacedDigit: Bool = false) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = "\(weight)|\(monospaced)|\(monospacedDigit)|\(text)"
        let w = widths[key] ?? {
            let f = nsFont(size: Self.probe, weight: weight, monospaced: monospaced, monospacedDigit: monospacedDigit)
            let v = ceil(NSAttributedString(string: text, attributes: [.font: f]).size().width)
            widths[key] = v
            return v
        }()
        return w * size / Self.probe
    }

    func lineHeight(size: CGFloat, weight: Font.Weight, monospaced: Bool = false) -> CGFloat {
        let key = "\(weight)|\(monospaced)"
        let h = lineHeights[key] ?? {
            let v = NSLayoutManager().defaultLineHeight(for: nsFont(size: Self.probe, weight: weight, monospaced: monospaced))
            lineHeights[key] = v
            return v
        }()
        return h * size / Self.probe
    }

    /// Наибольший кегль, при котором строка помещается в коробку (верхняя граница height/1.2, как у `fit` в Auto).
    func fittedSize(_ text: String, box: CGSize, weight: Font.Weight, monospaced: Bool = false, monospacedDigit: Bool = false) -> CGFloat {
        var s = box.height / 1.2
        let lh = lineHeight(size: s, weight: weight, monospaced: monospaced)
        if lh > box.height { s *= box.height / lh }
        let w = width(text, size: s, weight: weight, monospaced: monospaced, monospacedDigit: monospacedDigit)
        if w > box.width { s *= box.width / w }
        return max(1, s)
    }

    private static func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
