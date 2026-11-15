import Foundation

public enum SizeClass: String, Codable, Sendable, CaseIterable { case small, medium, large, extraLarge }

public enum FontDesign: String, Codable, Sendable, CaseIterable { case standard, rounded, monospaced, serif }

/// Выравнивание содержимого виджета (`ctx.theme.alignment`). `auto` — собственная раскладка виджета.
public enum ContentAlignment: String, Codable, Sendable, CaseIterable { case auto, left, center, right }

/// Режим фона виджета.
public enum BackgroundStyle: Codable, Equatable, Sendable {
    case liquidGlass
    case clear
    case color(hex: String, opacity: Double)
    case tint(hex: String, opacity: Double)
}

/// Тема, доступная в JS как `ctx.theme`.
public struct Theme: Codable, Equatable, Sendable {
    public var cornerRadius: Double
    public var fontDesign: FontDesign
    public var accentHex: String
    public var isDark: Bool
    public var alignment: ContentAlignment
    /// Имя семейства установленного шрифта; nil = брать `fontDesign`.
    public var fontFamily: String?
    /// Множитель размера текста; nil = Auto (виджеты сами подгоняют кегль под коробку через `fit`).
    public var textScale: Double?
    /// Вес текста: ultraLight...black; nil (или неизвестное значение) = Auto, собственные веса виджета.
    public var fontWeight: String?

    public init(cornerRadius: Double = 22, fontDesign: FontDesign = .standard,
                accentHex: String = "#0A84FF", isDark: Bool = false,
                alignment: ContentAlignment = .auto, fontFamily: String? = nil, textScale: Double? = nil,
                fontWeight: String? = nil) {
        self.cornerRadius = cornerRadius
        self.fontDesign = fontDesign
        self.accentHex = accentHex
        self.isDark = isDark
        self.alignment = alignment
        self.fontFamily = fontFamily
        self.textScale = textScale
        self.fontWeight = fontWeight
    }

    private enum CodingKeys: String, CodingKey { case cornerRadius, fontDesign, accentHex, isDark, alignment, fontFamily, textScale, fontWeight }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cornerRadius = try c.decode(Double.self, forKey: .cornerRadius)
        fontDesign = try c.decode(FontDesign.self, forKey: .fontDesign)
        accentHex = try c.decode(String.self, forKey: .accentHex)
        isDark = try c.decode(Bool.self, forKey: .isDark)
        alignment = try c.decodeIfPresent(ContentAlignment.self, forKey: .alignment) ?? .auto
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        textScale = try c.decodeIfPresent(Double.self, forKey: .textScale)
        fontWeight = try c.decodeIfPresent(String.self, forKey: .fontWeight)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(fontDesign, forKey: .fontDesign)
        try c.encode(accentHex, forKey: .accentHex)
        try c.encode(isDark, forKey: .isDark)
        try c.encode(alignment, forKey: .alignment)
        try c.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try c.encodeIfPresent(textScale, forKey: .textScale)
        try c.encodeIfPresent(fontWeight, forKey: .fontWeight)
    }
}
