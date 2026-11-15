import Layout
import SwiftUI

/// Окно «Layout»: прилипание, сетка и наглядный предпросмотр. Все изменения применяются сразу.
struct LayoutSettingsView: View {
    @ObservedObject var state: AppState
    @State private var customGrid = false

    private enum GridChoice: Hashable { case off, g4x3, g6x4, g8x5, custom }

    private var choice: Binding<GridChoice> {
        Binding(
            get: {
                let g = state.layout.grid
                if !g.enabled { return .off }
                if customGrid { return .custom }
                switch (g.columns, g.rows) {
                case (4, 3): return .g4x3
                case (6, 4): return .g6x4
                case (8, 5): return .g8x5
                default: return .custom
                }
            },
            set: { c in
                var g = state.layout.grid
                switch c {
                case .off: g.enabled = false
                case .g4x3: g.enabled = true; g.columns = 4; g.rows = 3; customGrid = false
                case .g6x4: g.enabled = true; g.columns = 6; g.rows = 4; customGrid = false
                case .g8x5: g.enabled = true; g.columns = 8; g.rows = 5; customGrid = false
                case .custom: g.enabled = true; customGrid = true
                }
                state.layout.grid = g
            })
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: DS.Space.l) {
                VStack(spacing: DS.Space.m) { snappingCard; gridCard }
                    .frame(width: 380)
                preview.frame(maxWidth: .infinity)
            }
            .padding(.vertical, DS.Space.xs).padding(.bottom, DS.Space.l)
        }
        .scrollClipDisabled()
        .onAppear {
            let g = state.layout.grid
            customGrid = g.enabled && ![(4, 3), (6, 4), (8, 5)].contains { $0.0 == g.columns && $0.1 == g.rows }
        }
    }

    // MARK: карточки

    private var snappingCard: some View {
        let snap = state.layout.snapEnabled
        return CardSection(title: "Snapping", symbol: "magnet", tint: .teal) {
            Toggle("Snapping", isOn: $state.layout.snapEnabled).toggleStyle(.switch)
            Group {
                Toggle("Screen center", isOn: $state.layout.snapToScreenCenter)
                Toggle("Screen edges", isOn: $state.layout.snapToScreenEdges)
                Toggle("Other widgets", isOn: $state.layout.snapToWidgets)
                SliderRow("Edge margin", value: $state.layout.edgeMargin, in: 0...100)
                    .disabled(!state.layout.snapToScreenEdges)
                SliderRow("Snap distance", value: $state.layout.snapThreshold, in: 2...40)
            }
            .disabled(!snap)
            Text("Hold ⌥ to snap temporarily off").font(.dsCaption).foregroundStyle(.secondary)
        }
    }

    private var gridCard: some View {
        CardSection(title: "Grid", symbol: "square.grid.3x3.fill", tint: .blue) {
            HStack(spacing: 6) {
                presetTile(.off, label: "Off", cols: 0, rows: 0)
                presetTile(.g4x3, label: "4×3", cols: 4, rows: 3)
                presetTile(.g6x4, label: "6×4", cols: 6, rows: 4)
                presetTile(.g8x5, label: "8×5", cols: 8, rows: 5)
                presetTile(.custom, label: "Custom", cols: min(state.layout.grid.columns, 12), rows: min(state.layout.grid.rows, 12))
            }
            if choice.wrappedValue == .custom {
                Stepper("Columns: \(state.layout.grid.columns)", value: $state.layout.grid.columns, in: GridSettings.columnsRange)
                Stepper("Rows: \(state.layout.grid.rows)", value: $state.layout.grid.rows, in: GridSettings.rowsRange)
            }
            Toggle("Show grid in edit mode", isOn: $state.layout.showGridInEditMode)
                .toggleStyle(.switch).disabled(!state.layout.grid.enabled)
            Text("Widget sizes are measured in cells: 1×1, 2×1, 2×2 and 4×2. With the grid on, widgets snap to cells.")
                .font(.dsCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spacingCard: some View {
        CardSection(title: "Margins", symbol: "rectangle.dashed", tint: .orange) {
            SliderRow("Gap between cells", value: $state.layout.grid.gap, in: GridSettings.gapRange)
            SliderRow("Margin from screen edge", value: $state.layout.grid.margin, in: 0...100)
        }
        .disabled(!state.layout.grid.enabled)
    }

    private func presetTile(_ c: GridChoice, label: String, cols: Int, rows: Int) -> some View {
        let selected = choice.wrappedValue == c
        return Button { choice.wrappedValue = c } label: {
            VStack(spacing: 6) {
                GridGlyph(cols: cols, rows: rows).frame(width: 44, height: 30)
                Text(label).font(.dsCaption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? DS.accent.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? DS.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c == .off ? "Grid off" : (c == .custom ? "Custom grid" : "Grid \(cols) by \(rows)"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: предпросмотр

    private var preview: some View {
        let size = NSScreen.screens.first?.frame.size ?? CGSize(width: 1440, height: 900)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            GroupHeader(title: "Live preview", symbol: "eye.fill", tint: MainSection.layout.tint)
            MiniDesktop { _ in EmptyView() }
                .overlay { LayoutPreview(layout: state.layout, screen: size) }
            Text(state.layout.grid.enabled
                 ? "Grid \(state.layout.grid.columns)×\(state.layout.grid.rows), gap \(Int(state.layout.grid.gap)) pt, margin \(Int(state.layout.grid.margin)) pt. Sample widgets: 4×2, 2×2, 2×1, 1×1."
                 : "Grid is off: widgets move freely. Sample widgets: 4×2, 2×2, 2×1, 1×1.")
                .font(.dsCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            spacingCard
        }
    }
}

/// Мини-схема сетки на плитке пресета.
private struct GridGlyph: View {
    let cols: Int
    let rows: Int
    var body: some View {
        Canvas { ctx, size in
            if cols == 0 || rows == 0 {
                ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 4),
                           with: .color(.primary.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                return
            }
            let gap: CGFloat = cols > 8 || rows > 8 ? 1 : 2
            let cw = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let ch = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for r in 0..<rows { for c in 0..<cols {
                let rect = CGRect(x: CGFloat(c) * (cw + gap), y: CGFloat(r) * (ch + gap), width: cw, height: ch)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, cw / 3)), with: .color(.primary.opacity(0.45)))
            } }
        }
        .accessibilityHidden(true)
    }
}

/// Сетка выбранного пресета (ячейки, зазоры, поля) и условные виджеты поверх мини-стола.
private struct LayoutPreview: View {
    let layout: LayoutSettings
    let screen: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Sample: Identifiable { let id: Int; let c: Int; let r: Int; let w: Int; let h: Int }

    /// Первое подходящее место для условных виджетов в сетке cols×rows.
    private func pack(cols: Int, rows: Int) -> [Sample] {
        var used = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var out: [Sample] = []
        for (i, s) in [(4, 2), (2, 2), (2, 1), (1, 1)].enumerated() {
            let (w, h) = s
            guard w <= cols, h <= rows else { continue }
            search: for r in 0...(rows - h) { for c in 0...(cols - w) {
                let free = (r..<r + h).allSatisfy { rr in (c..<c + w).allSatisfy { !used[rr][$0] } }
                if free {
                    for rr in r..<r + h { for cc in c..<c + w { used[rr][cc] = true } }
                    out.append(Sample(id: i, c: c, r: r, w: w, h: h)); break search
                }
            } }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let kx = W / screen.width
            let g = layout.grid
            let cols = g.enabled ? g.columns : 6, rows = g.enabled ? g.rows : 4
            let gap = (g.enabled ? g.gap : 12) * kx, m = (g.enabled ? g.margin : 24) * kx
            let cw = max(1, (W - 2 * m - gap * CGFloat(cols - 1)) / CGFloat(cols))
            let ch = max(1, (H - 2 * m - gap * CGFloat(rows - 1)) / CGFloat(rows))
            ZStack(alignment: .topLeading) {
                if g.enabled {
                    Canvas { ctx, _ in
                        for r in 0..<rows { for c in 0..<cols {
                            let rect = CGRect(x: m + CGFloat(c) * (cw + gap), y: m + CGFloat(r) * (ch + gap), width: cw, height: ch)
                            let p = Path(roundedRect: rect, cornerRadius: min(cw, ch) * 0.12)
                            ctx.fill(p, with: .color(.white.opacity(0.16)))
                            ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 0.7)
                        } }
                    }
                }
                if layout.snapEnabled && layout.snapToScreenEdges {
                    Rectangle().strokeBorder(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .padding(layout.edgeMargin * kx)
                }
                if layout.snapEnabled && layout.snapToScreenCenter {
                    Path { p in
                        p.move(to: CGPoint(x: W / 2, y: 0)); p.addLine(to: CGPoint(x: W / 2, y: H))
                        p.move(to: CGPoint(x: 0, y: H / 2)); p.addLine(to: CGPoint(x: W, y: H / 2))
                    }
                    .stroke(Color.yellow.opacity(0.6), style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
                }
                ForEach(pack(cols: cols, rows: rows)) { s in
                    let w: CGFloat = CGFloat(s.w) * cw + CGFloat(s.w - 1) * gap
                    let h: CGFloat = CGFloat(s.h) * ch + CGFloat(s.h - 1) * gap
                    let ox: CGFloat = m + CGFloat(s.c) * (cw + gap)
                    let oy: CGFloat = m + CGFloat(s.r) * (ch + gap)
                    SampleWidget(label: "\(s.w)×\(s.h)", width: w, height: h).offset(x: ox, y: oy)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: layout)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SampleWidget: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(width, height) * 0.16, style: .continuous)
        let fontSize: CGFloat = max(8, min(width, height) * 0.22)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(DS.accent.opacity(0.35))
            shape.strokeBorder(.white.opacity(0.7), lineWidth: 1)
            Text(label).font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 1)
        }
        .frame(width: width, height: height)
    }
}
