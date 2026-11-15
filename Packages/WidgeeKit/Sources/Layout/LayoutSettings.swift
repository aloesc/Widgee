import CoreGraphics
import Foundation

// Система координат всего модуля: как у AppKit, начало внизу слева, ось Y вверх.
// «Верх» прямоугольника — maxY, «низ» — minY. Строки сетки считаются сверху вниз (row 0 — верхняя).

public struct GridSettings: Codable, Equatable, Sendable {
    public static let columnsRange = 1...24
    public static let rowsRange = 1...24
    public static let gapRange: ClosedRange<CGFloat> = 0...64
    public static let marginRange: ClosedRange<CGFloat> = 0...200

    public static let preset4x3 = GridSettings(enabled: true, columns: 4, rows: 3)
    public static let preset6x4 = GridSettings(enabled: true, columns: 6, rows: 4)
    public static let preset8x5 = GridSettings(enabled: true, columns: 8, rows: 5)
    public static let presets: [GridSettings] = [preset4x3, preset6x4, preset8x5]

    public var enabled: Bool
    public var columns: Int
    public var rows: Int
    public var gap: CGFloat
    public var margin: CGFloat

    public init(enabled: Bool = false, columns: Int = 6, rows: Int = 4, gap: CGFloat = 12, margin: CGFloat = 24) {
        self.enabled = enabled
        self.columns = columns
        self.rows = rows
        self.gap = gap
        self.margin = margin
        self = clamped()
    }

    private enum CodingKeys: String, CodingKey { case enabled, columns, rows, gap, margin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            columns: try c.decodeIfPresent(Int.self, forKey: .columns) ?? 6,
            rows: try c.decodeIfPresent(Int.self, forKey: .rows) ?? 4,
            gap: try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? 12,
            margin: try c.decodeIfPresent(CGFloat.self, forKey: .margin) ?? 24
        )
    }

    /// Копия со значениями в допустимых диапазонах (NaN -> значение по умолчанию).
    public func clamped() -> GridSettings {
        var r = self
        r.columns = min(max(columns, Self.columnsRange.lowerBound), Self.columnsRange.upperBound)
        r.rows = min(max(rows, Self.rowsRange.lowerBound), Self.rowsRange.upperBound)
        r.gap = Self.clamp(gap, Self.gapRange, fallback: 12)
        r.margin = Self.clamp(margin, Self.marginRange, fallback: 24)
        return r
    }

    static func clamp(_ v: CGFloat, _ range: ClosedRange<CGFloat>, fallback: CGFloat) -> CGFloat {
        guard v.isFinite else { return fallback }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

public struct LayoutSettings: Codable, Equatable, Sendable {
    public var snapEnabled: Bool
    public var snapToScreenCenter: Bool
    public var snapToScreenEdges: Bool
    public var snapToWidgets: Bool
    public var edgeMargin: CGFloat
    public var snapThreshold: CGFloat
    public var grid: GridSettings
    public var showGridInEditMode: Bool

    public init(
        snapEnabled: Bool = true,
        snapToScreenCenter: Bool = true,
        snapToScreenEdges: Bool = true,
        snapToWidgets: Bool = true,
        edgeMargin: CGFloat = 20,
        snapThreshold: CGFloat = 10,
        grid: GridSettings = GridSettings(),
        showGridInEditMode: Bool = true
    ) {
        self.snapEnabled = snapEnabled
        self.snapToScreenCenter = snapToScreenCenter
        self.snapToScreenEdges = snapToScreenEdges
        self.snapToWidgets = snapToWidgets
        self.edgeMargin = edgeMargin.isFinite ? max(0, edgeMargin) : 20
        self.snapThreshold = snapThreshold.isFinite ? max(0, snapThreshold) : 10
        self.grid = grid
        self.showGridInEditMode = showGridInEditMode
    }

    private enum CodingKeys: String, CodingKey {
        case snapEnabled, snapToScreenCenter, snapToScreenEdges, snapToWidgets
        case edgeMargin, snapThreshold, grid, showGridInEditMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            snapEnabled: try c.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? true,
            snapToScreenCenter: try c.decodeIfPresent(Bool.self, forKey: .snapToScreenCenter) ?? true,
            snapToScreenEdges: try c.decodeIfPresent(Bool.self, forKey: .snapToScreenEdges) ?? true,
            snapToWidgets: try c.decodeIfPresent(Bool.self, forKey: .snapToWidgets) ?? true,
            edgeMargin: try c.decodeIfPresent(CGFloat.self, forKey: .edgeMargin) ?? 20,
            snapThreshold: try c.decodeIfPresent(CGFloat.self, forKey: .snapThreshold) ?? 10,
            grid: try c.decodeIfPresent(GridSettings.self, forKey: .grid) ?? GridSettings(),
            showGridInEditMode: try c.decodeIfPresent(Bool.self, forKey: .showGridInEditMode) ?? true
        )
    }
}
