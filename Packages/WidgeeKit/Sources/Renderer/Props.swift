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
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
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
