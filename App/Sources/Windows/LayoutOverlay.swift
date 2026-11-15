import AppKit
import Layout
import SwiftUI

@MainActor
final class OverlayModel: ObservableObject {
    @Published var frame: CGRect = .zero
    @Published var guides: [Guide] = []
    @Published var cells: [CGRect] = []
}

/// Рисует сетку ячеек и направляющие прилипания в координатах экрана (AppKit, начало внизу слева).
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Canvas { ctx, _ in
            let f = model.frame
            func local(_ r: CGRect) -> CGRect { CGRect(x: r.minX - f.minX, y: f.maxY - r.maxY, width: r.width, height: r.height) }
            for c in model.cells {
                let p = Path(roundedRect: local(c), cornerRadius: 6)
                ctx.fill(p, with: .color(Color(nsColor: .controlAccentColor).opacity(0.10)))
                ctx.stroke(p, with: .color(Color(nsColor: .controlAccentColor).opacity(0.45)), lineWidth: 1)
            }
            let color = Color(red: 0.95, green: 0.25, blue: 0.85)
            for g in model.guides {
                var path = Path()
                switch g.axis {
                case .vertical:
                    let x = g.position - f.minX
                    path.move(to: CGPoint(x: x, y: f.maxY - g.start))
                    path.addLine(to: CGPoint(x: x, y: f.maxY - g.end))
                case .horizontal:
                    let y = f.maxY - g.position
                    path.move(to: CGPoint(x: g.start - f.minX, y: y))
                    path.addLine(to: CGPoint(x: g.end - f.minX, y: y))
                }
                ctx.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .frame(width: model.frame.width, height: model.frame.height)
        .allowsHitTesting(false)
    }
}

/// Прозрачные click-through окна поверх виджетов (по одному на экран): сетка в режиме редактирования и направляющие.
@MainActor
final class LayoutOverlay {
    private var items: [String: (window: NSWindow, model: OverlayModel)] = [:]
    private(set) var guides: [Guide] = []
    private var guideScreen: NSScreen?

    func model(for screen: NSScreen) -> OverlayModel? { items[Self.key(screen, NSScreen.screens)]?.model }
    var windowNumbers: [Int] { items.values.map { $0.window.windowNumber } }

    private static func key(_ s: NSScreen, _ all: [NSScreen]) -> String {
        s.displayID.map(String.init) ?? "idx\(all.firstIndex(of: s) ?? 0)"
    }

    func setGuides(_ g: [Guide], on screen: NSScreen?) { guides = g; guideScreen = screen }

    func refresh(editing: Bool, layout: LayoutSettings) {
        let screens = NSScreen.screens
        var alive = Set<String>()
        for s in screens {
            let k = Self.key(s, screens)
            alive.insert(k)
            let showGrid = editing && layout.grid.enabled && layout.showGridInEditMode
            var cells: [CGRect] = []
            if showGrid {
                let g = SnapGridLayout(screen: s.visibleFrame, settings: layout.grid)
                if g.cellWidth > 0, g.cellHeight > 0 { cells = g.allCellRects }
            }
            let gs = (guideScreen == s) ? guides : []
            if cells.isEmpty && gs.isEmpty { items[k]?.window.orderOut(nil); continue }
            let item = items[k] ?? makeItem(k)
            item.model.frame = s.frame
            item.model.cells = cells
            item.model.guides = gs
            if item.window.frame != s.frame { item.window.setFrame(s.frame, display: false) }
            item.window.orderFrontRegardless()
        }
        for (k, v) in items where !alive.contains(k) { v.window.orderOut(nil); items[k] = nil }
    }

    private func makeItem(_ k: String) -> (window: NSWindow, model: OverlayModel) {
        let model = OverlayModel()
        let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.sizingOptions = []
        w.contentView = host
        items[k] = (w, model)
        return (w, model)
    }
}
