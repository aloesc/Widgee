import SwiftUI

/// Разобранный hex-цвет (компоненты 0...1).
public struct HexColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Разбирает `#RGB`, `#RRGGBB`, `#RRGGBBAA` (символ `#` необязателен). Иначе `nil`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let chars = Array(s)
        func byte(_ a: Character, _ b: Character) -> Double? {
            UInt8(String([a, b]), radix: 16).map { Double($0) / 255 }
        }
        switch chars.count {
        case 3:
            guard let r = byte(chars[0], chars[0]), let g = byte(chars[1], chars[1]),
                  let b = byte(chars[2], chars[2]) else { return nil }
            self.init(red: r, green: g, blue: b)
        case 6, 8:
            guard let r = byte(chars[0], chars[1]), let g = byte(chars[2], chars[3]),
                  let b = byte(chars[4], chars[5]) else { return nil }
            let a = chars.count == 8 ? byte(chars[6], chars[7]) : 1
            guard let a else { return nil }
            self.init(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    public func color(opacity: Double = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha * min(max(opacity, 0), 1))
    }
}

extension Color {
    /// Цвет из hex-строки; `nil` при неверном формате.
    public init?(hex: String, opacity: Double = 1) {
        guard let h = HexColor(hex: hex) else { return nil }
        self = h.color(opacity: opacity)
    }
}
