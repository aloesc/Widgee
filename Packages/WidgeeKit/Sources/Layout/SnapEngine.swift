import CoreGraphics
import Foundation

public struct Guide: Equatable, Sendable {
    public enum Axis: Sendable { case vertical, horizontal }
    public enum Kind: Int, Sendable { case screenCenter = 0, screenEdge, widgetEdge, widgetCenter, grid }

    public var axis: Axis
    /// vertical: x линии; horizontal: y линии.
    public var position: CGFloat
    /// Начало/конец отрезка вдоль линии (y для vertical, x для horizontal).
    public var start: CGFloat
    public var end: CGFloat
    public var kind: Kind

    public init(axis: Axis, position: CGFloat, start: CGFloat, end: CGFloat, kind: Kind) {
        self.axis = axis; self.position = position; self.start = start; self.end = end; self.kind = kind
    }
}

public struct SnapResult: Equatable, Sendable {
    public var rect: CGRect
    public var guides: [Guide]
}

public enum SnapEngine {
    private struct Candidate {
        var delta: CGFloat
        var kind: Guide.Kind
        var position: CGFloat
        var spanStart: CGFloat
        var spanEnd: CGFloat
    }

    public static func snap(moving: CGRect, others: [CGRect], screen: CGRect,
                            settings: LayoutSettings, disabled: Bool) -> SnapResult {
        let unchanged = SnapResult(rect: moving, guides: [])
        guard !disabled, settings.snapEnabled,
              moving.origin.x.isFinite, moving.origin.y.isFinite,
              moving.width.isFinite, moving.height.isFinite,
              screen.origin.x.isFinite, screen.origin.y.isFinite,
              screen.width.isFinite, screen.height.isFinite else { return unchanged }
        let threshold = settings.snapThreshold.isFinite ? max(0, settings.snapThreshold) : 0
        let others = others.filter { $0.origin.x.isFinite && $0.origin.y.isFinite && $0.width.isFinite && $0.height.isFinite }

        let gridOn = settings.grid.enabled
        let layout = GridLayout(screen: screen, settings: settings.grid)
        let screenValid = screen.width > 0 && screen.height > 0

        var cx: [Candidate] = [], cy: [Candidate] = []

        if gridOn {
            guard screenValid, layout.cellWidth > 0, layout.cellHeight > 0 else { return unchanged }
            let xs = (0..<layout.columns).map { layout.cellRect(column: $0, row: 0) }
            let ys = (0..<layout.rows).map { layout.cellRect(column: 0, row: $0) }
            let spanY = (screen.minY, screen.maxY), spanX = (screen.minX, screen.maxX)
            for r in xs {
                for (mv, t) in [(moving.minX, r.minX), (moving.maxX, r.maxX)] {
                    cx.append(Candidate(delta: t - mv, kind: .grid, position: t, spanStart: spanY.0, spanEnd: spanY.1))
                }
            }
            for r in ys {
                for (mv, t) in [(moving.minY, r.minY), (moving.maxY, r.maxY)] {
                    cy.append(Candidate(delta: t - mv, kind: .grid, position: t, spanStart: spanX.0, spanEnd: spanX.1))
                }
            }
        } else {
            if settings.snapToScreenCenter && screenValid {
                cx.append(Candidate(delta: screen.midX - moving.midX, kind: .screenCenter,
                                    position: screen.midX, spanStart: screen.minY, spanEnd: screen.maxY))
                cy.append(Candidate(delta: screen.midY - moving.midY, kind: .screenCenter,
                                    position: screen.midY, spanStart: screen.minX, spanEnd: screen.maxX))
            }
            if settings.snapToScreenEdges && screenValid {
                let m = settings.edgeMargin
                let l = screen.minX + m, r = screen.maxX - m, b = screen.minY + m, t = screen.maxY - m
                cx.append(Candidate(delta: l - moving.minX, kind: .screenEdge, position: l, spanStart: screen.minY, spanEnd: screen.maxY))
                cx.append(Candidate(delta: r - moving.maxX, kind: .screenEdge, position: r, spanStart: screen.minY, spanEnd: screen.maxY))
                cy.append(Candidate(delta: b - moving.minY, kind: .screenEdge, position: b, spanStart: screen.minX, spanEnd: screen.maxX))
                cy.append(Candidate(delta: t - moving.maxY, kind: .screenEdge, position: t, spanStart: screen.minX, spanEnd: screen.maxX))
            }
            if settings.snapToWidgets {
                for o in others {
                    for t in [o.minX, o.maxX] {
                        for mv in [moving.minX, moving.maxX] {
                            cx.append(Candidate(delta: t - mv, kind: .widgetEdge, position: t, spanStart: o.minY, spanEnd: o.maxY))
                        }
                    }
                    cx.append(Candidate(delta: o.midX - moving.midX, kind: .widgetCenter, position: o.midX, spanStart: o.minY, spanEnd: o.maxY))
                    for t in [o.minY, o.maxY] {
                        for mv in [moving.minY, moving.maxY] {
                            cy.append(Candidate(delta: t - mv, kind: .widgetEdge, position: t, spanStart: o.minX, spanEnd: o.maxX))
                        }
                    }
                    cy.append(Candidate(delta: o.midY - moving.midY, kind: .widgetCenter, position: o.midY, spanStart: o.minX, spanEnd: o.maxX))
                }
            }
        }

        var rect = moving
        var guides: [Guide] = []
        let bx = best(cx, threshold)
        let by = best(cy, threshold)
        if let bx { rect.origin.x += bx.delta }
        if let by { rect.origin.y += by.delta }
        // Отрезки гайдов считаем по итоговому rect.
        if let bx {
            let (s, e) = (min(bx.spanStart, rect.minY), max(bx.spanEnd, rect.maxY))
            guides.append(Guide(axis: .vertical, position: bx.position, start: s, end: e, kind: bx.kind))
        }
        if let by {
            let (s, e) = (min(by.spanStart, rect.minX), max(by.spanEnd, rect.maxX))
            guides.append(Guide(axis: .horizontal, position: by.position, start: s, end: e, kind: by.kind))
        }
        return SnapResult(rect: rect, guides: guides)
    }

    private static func best(_ cands: [Candidate], _ threshold: CGFloat) -> Candidate? {
        var result: Candidate?
        for c in cands where c.delta.isFinite && abs(c.delta) <= threshold {
            guard let r = result else { result = c; continue }
            let d = abs(c.delta), rd = abs(r.delta)
            if d < rd || (d == rd && c.kind.rawValue < r.kind.rawValue) { result = c }
        }
        return result
    }
}
