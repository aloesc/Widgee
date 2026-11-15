import CoreGraphics
import Foundation
import Testing
@testable import Layout

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private func snap(_ m: CGRect, others: [CGRect] = [], _ s: LayoutSettings = LayoutSettings(), disabled: Bool = false) -> SnapResult {
    SnapEngine.snap(moving: m, others: others, screen: screen, settings: s, disabled: disabled)
}

@Suite struct SnapEngineTests {
    @Test func centersOnBothAxes() {
        let r = snap(CGRect(x: 405, y: 305, width: 200, height: 200))
        #expect(r.rect == CGRect(x: 400, y: 300, width: 200, height: 200))
        #expect(r.guides.count == 2)
        #expect(r.guides.allSatisfy { $0.kind == .screenCenter })
        #expect(Set(r.guides.map(\.axis)) == [.vertical, .horizontal])
    }

    @Test func screenEdgesWithMargin() {
        let r = snap(CGRect(x: 26, y: 12, width: 100, height: 100))
        #expect(r.rect.origin == CGPoint(x: 20, y: 20))
        let r2 = snap(CGRect(x: 875, y: 685, width: 100, height: 100))
        #expect(r2.rect.maxX == 980)
        #expect(r2.rect.maxY == 780)
        #expect(r2.guides.allSatisfy { $0.kind == .screenEdge })
    }

    @Test func widgetEdgesAndCenters() {
        let other = CGRect(x: 100, y: 100, width: 100, height: 100)
        let e = snap(CGRect(x: 205, y: 250, width: 80, height: 80), others: [other])
        #expect(e.rect.minX == 200)
        #expect(e.guides.first { $0.axis == .vertical }?.kind == .widgetEdge)
        let c = snap(CGRect(x: 120, y: 500, width: 60, height: 60), others: [other])
        #expect(c.rect.midX == 150)
        #expect(c.guides.first { $0.axis == .vertical }?.kind == .widgetCenter || c.rect.minX == 100)
        let c2 = snap(CGRect(x: 300, y: 405, width: 100, height: 100), others: [CGRect(x: 600, y: 425, width: 40, height: 40)])
        #expect(c2.rect.midY == 445)
    }

    @Test func noSnapBeyondThreshold() {
        let m = CGRect(x: 300, y: 250, width: 100, height: 100)
        let r = snap(m, others: [CGRect(x: 500, y: 600, width: 50, height: 50)])
        #expect(r.rect == m)
        #expect(r.guides.isEmpty)
    }

    @Test func nearestWins() {
        // minX=24 (до края 4), другой виджет на maxX=30 (до него 6)
        let r = snap(CGRect(x: 24, y: 300, width: 100, height: 100), others: [CGRect(x: 0, y: 0, width: 30, height: 30)])
        #expect(r.rect.minX == 20)
    }

    @Test func priorityOnTie() {
        // экран-центр и край виджета на одинаковом расстоянии
        let other = CGRect(x: 300, y: 0, width: 200, height: 10) // maxX=500 == center
        let m = CGRect(x: 405, y: 300, width: 190, height: 100) // midX=500 -> delta=-0? use offset
        let r = snap(CGRect(x: m.minX - 3, y: m.minY, width: m.width, height: m.height), others: [other])
        #expect(r.guides.first { $0.axis == .vertical }?.kind == .screenCenter)
        var s = LayoutSettings(); s.snapToScreenCenter = false
        let edgeVsCenter = snap(CGRect(x: 100, y: 300, width: 100, height: 100),
                                others: [CGRect(x: 100, y: 0, width: 100, height: 10)], s)
        #expect(edgeVsCenter.guides.first { $0.axis == .vertical }?.kind == .widgetEdge)
    }

    @Test func disabledAndSnapOff() {
        let m = CGRect(x: 405, y: 305, width: 200, height: 200)
        #expect(snap(m, disabled: true) == SnapResult(rect: m, guides: []))
        var s = LayoutSettings(); s.snapEnabled = false
        #expect(snap(m, s).rect == m)
        #expect(snap(m, s).guides.isEmpty)
    }

    @Test func gridTakesPriorityOverCenterAndEdges() {
        var s = LayoutSettings()
        s.grid = GridSettings(enabled: true, columns: 4, rows: 3, gap: 0, margin: 0)
        // центр экрана x=500 совпал бы, но сетка 4 колонки: линии 0,250,500,... 500 тоже линия -> берем без центра
        let r = snap(CGRect(x: 255, y: 5, width: 100, height: 100), s)
        #expect(r.rect.minX == 250)
        #expect(r.guides.allSatisfy { $0.kind == .grid })
        let far = snap(CGRect(x: 120, y: 330, width: 100, height: 100), s)
        #expect(far.guides.isEmpty || far.guides.allSatisfy { $0.kind == .grid })
    }

    @Test func degenerateInputs() {
        let nan = CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)
        #expect(snap(nan).guides.isEmpty)
        let r = SnapEngine.snap(moving: CGRect(x: 1, y: 1, width: 10, height: 10), others: [],
                                screen: .zero, settings: LayoutSettings(), disabled: false)
        #expect(r.rect.size == CGSize(width: 10, height: 10))
        var s = LayoutSettings(); s.grid.enabled = true
        let g = SnapEngine.snap(moving: CGRect(x: 1, y: 1, width: 10, height: 10), others: [],
                                screen: CGRect(x: 0, y: 0, width: -5, height: 0), settings: s, disabled: false)
        #expect(g.guides.isEmpty)
    }
}

@Suite struct GridLayoutTests {
    private func layout(_ c: Int = 6, _ r: Int = 4, gap: CGFloat = 12, margin: CGFloat = 24) -> GridLayout {
        GridLayout(screen: screen, settings: GridSettings(enabled: true, columns: c, rows: r, gap: gap, margin: margin))
    }

    @Test func cellsInsideScreenWithoutOverlap() {
        let l = layout()
        let cells = l.allCellRects
        #expect(cells.count == 24)
        for c in cells { #expect(screen.contains(c)) }
        for i in 0..<cells.count { for j in (i + 1)..<cells.count {
            #expect(!cells[i].intersects(cells[j]))
        } }
        #expect(cells[0].minX == 24)
        #expect(abs(cells[0].maxY - 776) < 1e-9) // строка 0 — сверху
    }

    @Test func snapOriginSizeAndSnapped() {
        let l = layout()
        let c = l.cellRect(column: 2, row: 1)
        let o = l.snapOrigin(for: CGRect(x: c.minX + 5, y: c.minY - 4, width: 10, height: 10).offsetBy(dx: 0, dy: c.height))
        #expect(o.col == 2 && o.row == 1)
        let two = l.rect(forSpan: GridSpan(columns: 2, rows: 2), at: GridCell(column: 1, row: 1))
        let sz = l.snapSize(for: CGSize(width: two.width + 7, height: two.height - 5))
        #expect(sz.colSpan == 2 && sz.rowSpan == 2)
        #expect(l.snapSize(for: CGSize(width: 1, height: 1)) == (1, 1))
        #expect(l.snapSize(for: CGSize(width: 99999, height: 99999)) == (6, 4))
        let sn = l.snapped(two.offsetBy(dx: 6, dy: -4).insetBy(dx: 3, dy: 3))
        #expect(abs(sn.minX - two.minX) < 1e-9 && abs(sn.width - two.width) < 1e-9 && abs(sn.height - two.height) < 1e-9)
        #expect(abs(sn.maxY - two.maxY) < 1e-9)
    }

    @Test func clampingToBounds() {
        let l = layout()
        let o = l.snapOrigin(for: CGRect(x: -500, y: 5000, width: 10, height: 10))
        #expect(o.col == 0 && o.row == 0)
        let o2 = l.snapOrigin(for: CGRect(x: 5000, y: -5000, width: 10, height: 10))
        #expect(o2.col == 5 && o2.row == 3)
        let big = l.rect(forSpan: GridSpan(columns: 4, rows: 2), at: GridCell(column: 5, row: 3))
        #expect(screen.contains(big))
    }

    @Test func presetSpans() {
        #expect(GridLayout.spans(for: .s, columns: 4, rows: 3) == (1, 1))
        #expect(GridLayout.spans(for: .m, columns: 4, rows: 3) == (2, 1))
        #expect(GridLayout.spans(for: .l, columns: 4, rows: 3) == (2, 2))
        #expect(GridLayout.spans(for: .xl, columns: 4, rows: 3) == (4, 2))
        #expect(GridLayout.spans(for: .xl, columns: 6, rows: 4) == (4, 2))
        #expect(GridLayout.spans(for: .xl, columns: 2, rows: 1) == (2, 1))
        #expect(GridLayout.spans(for: .l, columns: 0, rows: 0) == (1, 1))
    }

    @Test func degenerate() {
        let tiny = GridLayout(screen: CGRect(x: 0, y: 0, width: 10, height: 10), settings: GridSettings(enabled: true, columns: 24, rows: 24, gap: 64, margin: 200))
        #expect(tiny.cellWidth == 0)
        #expect(tiny.allCellRects.count == 576)
        let r = CGRect(x: 3, y: 4, width: 5, height: 6)
        #expect(tiny.snapped(r) == r)
        let bad = GridLayout(screen: CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: -1, height: CGFloat.nan), settings: GridSettings())
        _ = bad.allCellRects
        #expect(bad.snapOrigin(for: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1)) == (0, 0))
        #expect(layout().snapped(CGRect(x: CGFloat.infinity, y: 0, width: CGFloat.nan, height: 1)).width.isNaN)
    }
}

@Suite struct LayoutSettingsTests {
    @Test func decodeEmptyAndPartial() throws {
        let d = JSONDecoder()
        #expect(try d.decode(LayoutSettings.self, from: Data("{}".utf8)) == LayoutSettings())
        let p = try d.decode(LayoutSettings.self, from: Data(#"{"edgeMargin":8,"grid":{"enabled":true,"columns":8}}"#.utf8))
        #expect(p.edgeMargin == 8 && p.snapThreshold == 10 && p.snapToWidgets)
        #expect(p.grid.enabled && p.grid.columns == 8 && p.grid.rows == 4 && p.grid.gap == 12)
    }

    @Test func defaultsPresetsClampAndRoundTrip() throws {
        let s = LayoutSettings()
        #expect(s.snapEnabled && s.edgeMargin == 20 && s.snapThreshold == 10 && s.showGridInEditMode)
        #expect(!s.grid.enabled && s.grid.columns == 6 && s.grid.rows == 4 && s.grid.gap == 12 && s.grid.margin == 24)
        #expect(GridSettings.presets.map { [$0.columns, $0.rows] } == [[4, 3], [6, 4], [8, 5]])
        let g = GridSettings(columns: 99, rows: 0, gap: 500, margin: -3)
        #expect(g.columns == 24 && g.rows == 1 && g.gap == 64 && g.margin == 0)
        var t = LayoutSettings(); t.grid = GridSettings.preset8x5; t.snapThreshold = 5
        let back = try JSONDecoder().decode(LayoutSettings.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }
}
