import Foundation

public enum SizeClass: String, Codable, Sendable, CaseIterable { case small, medium, large, extraLarge }

public enum FontDesign: String, Codable, Sendable, CaseIterable { case standard, rounded, monospaced }

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

    public init(cornerRadius: Double = 22, fontDesign: FontDesign = .standard,
                accentHex: String = "#0A84FF", isDark: Bool = false,
                alignment: ContentAlignment = .auto) {
        self.cornerRadius = cornerRadius
        self.fontDesign = fontDesign
        self.accentHex = accentHex
        self.isDark = isDark
        self.alignment = alignment
    }

    private enum CodingKeys: String, CodingKey { case cornerRadius, fontDesign, accentHex, isDark, alignment }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cornerRadius = try c.decode(Double.self, forKey: .cornerRadius)
        fontDesign = try c.decode(FontDesign.self, forKey: .fontDesign)
        accentHex = try c.decode(String.self, forKey: .accentHex)
        isDark = try c.decode(Bool.self, forKey: .isDark)
        alignment = try c.decodeIfPresent(ContentAlignment.self, forKey: .alignment) ?? .auto
    }
}
