import CoreGraphics
import Foundation

/// Пресеты размера виджета в ячейках сетки.
public enum GridSizePreset: String, CaseIterable, Codable, Sendable {
    case s = "S", m = "M", l = "L", xl = "XL"
}

public struct GridCell: Equatable, Sendable {
    public var column: Int
    public var row: Int
    public init(column: Int, row: Int) { self.column = column; self.row = row }
}

public struct GridSpan: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public init(columns: Int, rows: Int) { self.columns = columns; self.rows = rows }
}

/// Сетка на видимой области экрана. Координаты AppKit (начало внизу слева);
/// строка 0 — верхняя (у maxY), колонка 0 — левая.
public struct GridLayout: Equatable, Sendable {
    public let screen: CGRect
    public let settings: GridSettings
    public let columns: Int
    public let rows: Int
    public let gap: CGFloat
    public let margin: CGFloat
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat

    public init(screen: CGRect, settings: GridSettings) {
        let s = settings.clamped()
        let valid = screen.origin.x.isFinite && screen.origin.y.isFinite
            && screen.width.isFinite && screen.height.isFinite
            && screen.width > 0 && screen.height > 0
        self.screen = valid ? screen : CGRect(x: screen.origin.x.isFinite ? screen.origin.x : 0,
                                              y: screen.origin.y.isFinite ? screen.origin.y : 0,
                                              width: 0, height: 0)
        self.settings = s
        columns = s.columns
        rows = s.rows
        gap = s.gap
        margin = s.margin
        let w = self.screen.width - 2 * s.margin - s.gap * CGFloat(s.columns - 1)
        let h = self.screen.height - 2 * s.margin - s.gap * CGFloat(s.rows - 1)
        cellWidth = max(0, w / CGFloat(s.columns))
        cellHeight = max(0, h / CGFloat(s.rows))
    }

    private var pitchX: CGFloat { cellWidth + gap }
    private var pitchY: CGFloat { cellHeight + gap }

    private func clampCol(_ c: Int) -> Int { min(max(c, 0), columns - 1) }
    private func clampRow(_ r: Int) -> Int { min(max(r, 0), rows - 1) }

    public func cellRect(column: Int, row: Int) -> CGRect {
        rect(forSpan: GridSpan(columns: 1, rows: 1), at: GridCell(column: column, row: row))
    }

    /// Прямоугольник области span×span, начиная с ячейки `at` (левый верхний угол); клампится по границам сетки.
    public func rect(forSpan span: GridSpan, at cell: GridCell) -> CGRect {
        let cs = min(max(span.columns, 1), columns)
        let rs = min(max(span.rows, 1), rows)
        let col = min(max(cell.column, 0), columns - cs)
        let row = min(max(cell.row, 0), rows - rs)
        let w = CGFloat(cs) * cellWidth + CGFloat(cs - 1) * gap
        let h = CGFloat(rs) * cellHeight + CGFloat(rs - 1) * gap
        let x = screen.minX + margin + CGFloat(col) * pitchX
        let top = screen.maxY - margin - CGFloat(row) * pitchY
        return CGRect(x: x, y: top - h, width: w, height: h)
    }

    /// Ближайшая ячейка к левому верхнему углу rect.
    public func snapOrigin(for rect: CGRect) -> (col: Int, row: Int) {
        guard rect.minX.isFinite, rect.maxY.isFinite, pitchX > 0, pitchY > 0 else { return (0, 0) }
        let c = ((rect.minX - (screen.minX + margin)) / pitchX).rounded()
        let r = (((screen.maxY - margin) - rect.maxY) / pitchY).rounded()
        return (clampCol(Self.toInt(c)), clampRow(Self.toInt(r)))
    }

    /// Размер в ячейках (минимум 1×1, максимум — размер сетки).
    public func snapSize(for size: CGSize) -> (colSpan: Int, rowSpan: Int) {
        guard size.width.isFinite, size.height.isFinite, pitchX > 0, pitchY > 0 else { return (1, 1) }
        let c = Self.toInt(((size.width + gap) / pitchX).rounded())
        let r = Self.toInt(((size.height + gap) / pitchY).rounded())
        return (min(max(c, 1), columns), min(max(r, 1), rows))
    }

    public func snapped(_ rect: CGRect) -> CGRect {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              cellWidth > 0, cellHeight > 0 else { return rect }
        let size = snapSize(for: rect.size)
        let o = snapOrigin(for: rect)
        return self.rect(forSpan: GridSpan(columns: size.colSpan, rows: size.rowSpan),
                         at: GridCell(column: o.col, row: o.row))
    }

    /// S=1×1, M=2×1, L=2×2, XL=4×2, ограничено размером сетки.
    public static func spans(for preset: GridSizePreset, columns: Int, rows: Int) -> (cols: Int, rows: Int) {
        let base: (Int, Int)
        switch preset {
        case .s: base = (1, 1)
        case .m: base = (2, 1)
        case .l: base = (2, 2)
        case .xl: base = (4, 2)
        }
        return (min(base.0, max(columns, 1)), min(base.1, max(rows, 1)))
    }

    /// Все ячейки (по строкам сверху вниз) для оверлея.
    public var allCellRects: [CGRect] {
        var out: [CGRect] = []
        out.reserveCapacity(columns * rows)
        for r in 0..<rows { for c in 0..<columns { out.append(cellRect(column: c, row: r)) } }
        return out
    }

    private static func toInt(_ v: CGFloat) -> Int {
        guard v.isFinite else { return 0 }
        return Int(max(-1e6, min(1e6, v)))
    }
}
