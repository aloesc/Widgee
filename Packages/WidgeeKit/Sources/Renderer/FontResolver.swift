import AppKit
import SwiftUI

/// Подбор PostScript-имени шрифта по семейству и весу (nil, если семейство не установлено).
public enum FontResolver {
    private static func target(_ w: Font.Weight) -> Int {
        // Шкала NSFontManager: 5 = Regular, 6 = Medium (semibold), 8 = Bold, 9 = Heavy.
        switch w {
        case .ultraLight, .thin: 2
        case .light: 3
        case .medium: 6
        case .semibold: 7
        case .bold: 9
        case .heavy, .black: 10
        default: 5
        }
    }

    public static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family)?.isEmpty == false
    }

    /// true, если у семейства есть начертание ровно такого веса (иначе берётся ближайшее).
    public static func hasExactWeight(family: String, weight: Font.Weight) -> Bool {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else { return false }
        let want = target(weight)
        return members.contains { ((($0[3] as? Int) ?? 0) & Int(NSFontTraitMask.italicFontMask.rawValue)) == 0 && (($0[2] as? Int) ?? 5) == want }
    }

    public static func postScriptName(family: String, weight: Font.Weight) -> String? {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else { return nil }
        // member: [postScriptName, styleName, weight(Int), traits(Int)]
        let want = target(weight)
        let upright = members.filter { (($0[3] as? Int) ?? 0) & Int(NSFontTraitMask.italicFontMask.rawValue) == 0 }
        let pool = upright.isEmpty ? members : upright
        let best = pool.min { a, b in
            abs(((a[2] as? Int) ?? 5) - want) < abs(((b[2] as? Int) ?? 5) - want)
        }
        return best?[0] as? String
    }
}
