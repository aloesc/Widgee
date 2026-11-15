import SwiftUI
import WidgeeCore
import Background

/// Безопасный доступ к props: неверный тип -> `nil`/дефолт, без краша.
struct Props {
    static let maxPoints = 500
    let raw: [String: JSONValue]

    init(_ raw: [String: JSONValue]) { self.raw = raw }

    func string(_ k: String) -> String? { raw[k]?.stringValue }
    func bool(_ k: String) -> Bool? { raw[k]?.boolValue }
    func double(_ k: String) -> Double? {
        guard let v = raw[k]?.numberValue, v.isFinite else { return nil }
        return v
    }
    /// Размер/длина: конечное число в 0...4000.
    func length(_ k: String) -> CGFloat? {
        double(k).map { CGFloat(min(max($0, 0), 4000)) }
    }
    func int(_ k: String, in range: ClosedRange<Int>) -> Int? {
        double(k).map { Int(min(max($0, Double(range.lowerBound)), Double(range.upperBound)).rounded()) }
    }
    /// Значение бара, зажатое в 0...1 (по умолчанию 0).
    func unit(_ k: String = "value") -> Double { Props.clamp01(double(k) ?? 0) }
    func numbers(_ k: String) -> [Double] {
        guard case .array(let a)? = raw[k] else { return [] }
        return a.prefix(Props.maxPoints).compactMap { $0.numberValue }.filter { $0.isFinite }
    }
    func strings(_ k: String) -> [String] {
        guard case .array(let a)? = raw[k] else { return [] }
        return a.prefix(Props.maxPoints).map { $0.stringValue ?? "" }
    }

    static func clamp01(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }
}

/// Контекст отрисовки, передаваемый вниз по дереву.
struct RenderContext {
    var theme: Theme
    var sizeClass: SizeClass
    /// Ручной «Text size»: множитель `size` обычного текста и множитель кегля в коробке `fit` (см. `TextScalePass`).
    var textMultiplier: CGFloat = 1
    var fitScale: CGFloat = 1

    var manual: Bool { theme.textScale != nil }

    /// Масштаб дефолтных размеров по классу виджета.
    var scale: CGFloat {
        switch sizeClass {
        case .small: 0.9
        case .medium: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }

    var accent: Color { Color(hex: theme.accentHex) ?? .accentColor }

    /// "accent" | "primary" | "secondary" | "#hex"; иначе `fallback`.
    func color(_ name: String?, fallback: Color? = nil) -> Color {
        let fb = fallback ?? .primary
        guard let name else { return fb }
        switch name.lowercased() {
        case "accent": return accent
        case "primary": return .primary
        case "secondary": return .secondary
        default: return Color(hex: name) ?? fb
        }
    }

    var design: Font.Design {
        switch theme.fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }

    /// Коробка для `fit`: нужны и `width`, и `height`. Работает и в Auto, и при ручном «Text size».
    func fitBox(_ p: Props) -> CGSize? {
        guard p.bool("fit") ?? false, let w = p.length("width"), let h = p.length("height"), w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Кегль текста в коробке `fit`. Auto: верхняя граница height/1.2, дальше сжимает SwiftUI.
    /// Вручную: кегль, вписанный по реальным метрикам шрифта, умноженный на `fitScale`.
    @MainActor func fitSize(_ t: TextSpec, box: CGSize) -> CGFloat {
        guard manual else { return box.height / 1.2 }
        return TextMetrics(theme: theme).fittedSize(t.text, box: box, weight: t.weight, monospaced: t.monospaced,
                                                    monospacedDigit: t.monospacedDigit) * fitScale
    }

    /// Вес, заданный пользователем (`theme.fontWeight`); nil = Auto.
    var weightOverride: Font.Weight? { parseWeightStrict(theme.fontWeight) }

    /// Единая точка выбора шрифта: `theme.fontFamily` (если установлен) иначе системный шрифт с `fontDesign`.
    /// Размер берётся как есть: ручной множитель применяет вызывающий (`textMultiplier` / `fitSize`).
    func font(size: CGFloat, weight ownWeight: Font.Weight = .regular) -> Font {
        let weight = weightOverride ?? ownWeight
        if let family = theme.fontFamily, !family.isEmpty,
           let name = FontResolver.postScriptName(family: family, weight: weight) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: weight, design: design)
    }
}

func parseWeight(_ name: String?) -> Font.Weight {
    switch name?.lowercased() {
    case "ultralight": .ultraLight
    case "thin": .thin
    case "light": .light
    case "medium": .medium
    case "semibold": .semibold
    case "bold": .bold
    case "heavy": .heavy
    case "black": .black
    default: .regular
    }
}

/// Как `parseWeight`, но неизвестное/пустое значение даёт nil (Auto).
func parseWeightStrict(_ name: String?) -> Font.Weight? {
    switch name?.lowercased() {
    case "ultralight": .ultraLight
    case "thin": .thin
    case "light": .light
    case "regular": .regular
    case "medium": .medium
    case "semibold": .semibold
    case "bold": .bold
    case "heavy": .heavy
    case "black": .black
    default: nil
    }
}
