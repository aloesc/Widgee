import AppKit
import Combine
import SwiftUI

@MainActor
final class EditPanelModel: ObservableObject {
    @Published var collapsed = UserDefaults.standard.bool(forKey: "editPanel.collapsed") {
        didSet { UserDefaults.standard.set(collapsed, forKey: "editPanel.collapsed") }
    }
}

/// Хостинг, сообщающий о каждом layout: по нему панель подгоняется под фактический размер содержимого.
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Сохранённая позиция панели относительно экрана: смещение центра от центра видимой области, отступ от верхнего/нижнего края.
private struct SavedPanelPosition: Codable {
    var displayID: UInt32
    var dx: Double
    var top: Bool
    var inset: Double
}

/// Плавающая стеклянная капсула «Editing widgets» на время режима редактирования.
/// Позволяет выйти из режима без главного окна и без значка в строке меню.
/// По умолчанию стоит по центру сверху (или снизу, если сверху перекрывает виджеты); перетаскивается, сворачивается в кнопку Done.
@MainActor
final class EditPanelController {
    private unowned let state: AppState
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    private let model = EditPanelModel()
    private var bag = Set<AnyCancellable>()
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var refitScheduled = false
    private var resizeObserver: NSObjectProtocol?
    private var lastFit = NSSize.zero
    private static let key = "editPanel.position"
    private static let margin: CGFloat = 10

    init(state: AppState) {
        self.state = state
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.removeObject(forKey: Self.key)   // конфигурация экранов изменилась: позиция сбрасывается
                self?.place()
            }
        }
        model.$collapsed.dropFirst().sink { [weak self] _ in self?.scheduleRefit() }.store(in: &bag)
        state.desktop.onGestureChange = { [weak self] on in self?.setGestureActive(on) }
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func setVisible(_ on: Bool) {
        if !on { panel?.orderOut(nil); return }
        if panel == nil { panel = makePanel() }
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        fitSize()
        place()
        panel?.orderFrontRegardless()
        #if DEBUG
        scheduleDebugReport()
        #endif
    }

    private func makePanel() -> NSPanel {
        let host = PanelHostingView(rootView: EditPanelView(
            model: model,
            layout: { [weak state] in state?.openLayout() },
            done: { [weak state] in state?.isEditing = false },
            reset: { [weak self] in self?.resetPosition() },
            dragChanged: { [weak self] in self?.dragChanged() },
            dragEnded: { [weak self] in self?.dragEnded() }))
        host.sizingOptions = [.intrinsicContentSize]
        host.onLayout = { [weak self] in self?.scheduleRefit() }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 2 * ceil(host.intrinsicContentSize.width / 2), height: 2 * ceil(host.intrinsicContentSize.height / 2))),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.contentView = host
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.dragStart == nil { self?.place() } }   // AppKit может округлить размер: центр пересчитывается по фактическому
        }
        return p
    }

    // MARK: размер

    private func scheduleRefit() {
        guard !refitScheduled else { return }
        refitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refitScheduled = false
            if self.fitSize() { self.place() }
        }
    }

    /// Подгоняет окно под фактический размер содержимого (после layout и при смене состояния). true, если размер изменился.
    @discardableResult
    private func fitSize() -> Bool {
        guard let p = panel, let host = p.contentView as? PanelHostingView<EditPanelView> else { return false }
        host.layoutSubtreeIfNeeded()
        let raw = host.intrinsicContentSize
        // Чётные целые размеры: центр окна попадает на целый пиксель без дробного округления.
        let size = NSSize(width: 2 * ceil(raw.width / 2), height: 2 * ceil(raw.height / 2))
        guard size.width > 1, size.height > 1,
              abs(size.width - lastFit.width) > 0.5 || abs(size.height - lastFit.height) > 0.5 else { return false }
        lastFit = size
        var f = p.frame
        f.size = size
        p.setFrame(f, display: true)
        return true
    }

    // MARK: позиция

    private func targetScreen() -> NSScreen? {
        let frames = state.desktop.widgetFrames
        var counts: [ObjectIdentifier: (NSScreen, Int)] = [:]
        for f in frames {
            guard let s = NSScreen.screens.max(by: { Self.area($0.frame.intersection(f)) < Self.area($1.frame.intersection(f)) }),
                  Self.area(s.frame.intersection(f)) > 0 else { continue }
            counts[ObjectIdentifier(s), default: (s, 0)].1 += 1
        }
        return counts.values.max { $0.1 < $1.1 }?.0 ?? NSScreen.screens.first
    }

    private static func area(_ r: NSRect) -> CGFloat { r.isNull || r.isEmpty ? 0 : r.width * r.height }

    private func saved() -> SavedPanelPosition? {
        UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SavedPanelPosition.self, from: $0) }
    }

    private func clamp(_ o: NSPoint, size: NSSize, in vf: NSRect) -> NSPoint {
        NSPoint(x: min(max(o.x, vf.minX), max(vf.minX, vf.maxX - size.width)),
                y: min(max(o.y, vf.minY), max(vf.minY, vf.maxY - size.height)))
    }

    /// Сохранённая позиция (если экран на месте) или умная начальная: верх по центру, иначе низ, если верх перекрывает виджеты.
    private func place() {
        guard let p = panel else { return }
        let size = p.frame.size
        if let sv = saved(), let s = NSScreen.screens.first(where: { $0.displayID == sv.displayID }) {
            let vf = s.visibleFrame
            let x = vf.midX + sv.dx - size.width / 2
            let y = sv.top ? vf.maxY - sv.inset - size.height : vf.minY + sv.inset
            p.setFrameOrigin(clamp(NSPoint(x: x, y: y), size: size, in: vf))
            return
        }
        guard let s = targetScreen() else { return }
        let vf = s.visibleFrame
        let x = vf.midX - size.width / 2
        let top = NSRect(x: x, y: vf.maxY - size.height - Self.margin, width: size.width, height: size.height)
        let bottom = NSRect(x: x, y: vf.minY + Self.margin, width: size.width, height: size.height)
        let widgets = state.desktop.widgetFrames
        let topFree = !widgets.contains { $0.intersects(top) }
        let bottomFree = !widgets.contains { $0.intersects(bottom) }
        let chosen = (!topFree && bottomFree) ? bottom : top
        var o = clamp(chosen.origin, size: size, in: vf)
        o.x = o.x.rounded()
        if o != p.frame.origin { p.setFrameOrigin(o) }
        #if DEBUG
        dlog("editPanel placement: \(chosen == top ? "top" : "bottom") size=\(size) topFree=\(topFree) bottomFree=\(bottomFree)")
        #endif
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        place()
    }

    private func savePosition() {
        guard let p = panel else { return }
        let f = p.frame
        guard let s = NSScreen.screens.max(by: { Self.area($0.frame.intersection(f)) < Self.area($1.frame.intersection(f)) }),
              let id = s.displayID else { return }
        let vf = s.visibleFrame
        let top = (vf.maxY - f.maxY) <= (f.minY - vf.minY)
        let sv = SavedPanelPosition(displayID: id, dx: f.midX - vf.midX, top: top,
                                    inset: top ? vf.maxY - f.maxY : f.minY - vf.minY)
        if let d = try? JSONEncoder().encode(sv) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    // MARK: перетаскивание панели (за фон; кнопки остаются кнопками)

    private func dragChanged() {
        guard let p = panel else { return }
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (m, p.frame.origin) }
        guard let st = dragStart else { return }
        var o = NSPoint(x: st.origin.x + m.x - st.mouse.x, y: st.origin.y + m.y - st.mouse.y)
        let probe = NSRect(origin: o, size: p.frame.size)
        let s = NSScreen.screens.first { $0.frame.contains(m) }
            ?? NSScreen.screens.max { Self.area($0.frame.intersection(probe)) < Self.area($1.frame.intersection(probe)) }
        if let vf = s?.visibleFrame { o = clamp(o, size: p.frame.size, in: vf) }
        p.setFrameOrigin(o)
    }

    private func dragEnded() {
        guard dragStart != nil else { return }
        dragStart = nil
        savePosition()
    }

    // MARK: жест над виджетом

    /// На время перетаскивания/ресайза виджета панель полупрозрачна и пропускает мышь.
    private func setGestureActive(_ on: Bool) {
        guard let p = panel, p.isVisible else { return }
        p.ignoresMouseEvents = on
        let alpha: CGFloat = on ? 0.25 : 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            p.alphaValue = alpha
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.animator().alphaValue = alpha
            }
        }
        #if DEBUG
        dlog("editPanel gesture active=\(on) targetAlpha=\(alpha) ignoresMouseEvents=\(p.ignoresMouseEvents)")
        Task { @MainActor [weak p] in
            try? await Task.sleep(for: .milliseconds(400))
            if let p { dlog("editPanel gesture active=\(on) settledAlpha=\(String(format: "%.2f", p.alphaValue)) ignoresMouseEvents=\(p.ignoresMouseEvents)") }
        }
        #endif
    }

    #if DEBUG
    func debugSetCollapsed(_ v: Bool) { model.collapsed = v }

    /// Измеряет окно панели через CGWindowList (по PID) и сравнивает центр с центром видимой области экрана.
    private func scheduleDebugReport() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let p = self.panel, p.isVisible else { return }
            let pid = ProcessInfo.processInfo.processIdentifier
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            guard let info = list.first(where: { ($0[kCGWindowNumber as String] as? Int) == p.windowNumber && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }),
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let screen = NSScreen.screens.max(by: { Self.area($0.frame.intersection(p.frame)) < Self.area($1.frame.intersection(p.frame)) })
            else { dlog("editPanel: window not found in CGWindowList"); return }
            let mid = (b["X"] ?? 0) + (b["Width"] ?? 0) / 2
            dlog("editPanel intrinsic=\(p.contentView!.intrinsicContentSize) fitting=\(p.contentView!.fittingSize) contentMin=\(p.contentMinSize) contentMax=\(p.contentMaxSize) lastFit=\(self.lastFit)")
            dlog("editPanel midX=\(mid) screenMidX=\(screen.visibleFrame.midX) width=\(b["Width"] ?? 0) cgBounds=\(b) panelFrame=\(p.frame) visible=\(screen.visibleFrame) windowID=\(p.windowNumber) collapsed=\(self.model.collapsed)")
        }
    }
    #endif
}

fileprivate struct EditPanelView: View {
    @ObservedObject var model: EditPanelModel
    let layout: () -> Void
    let done: () -> Void
    let reset: () -> Void
    let dragChanged: () -> Void
    let dragEnded: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.collapsed { collapsedBody } else { expandedBody }
        }
        .padding(6)
        .fixedSize()
        .contextMenu {
            Button("Reset position", action: reset)
            Button(model.collapsed ? "Expand panel" : "Collapse panel") { toggle() }
        }
    }

    private func toggle() {
        if reduceMotion { model.collapsed.toggle() } else { withAnimation(.snappy(duration: 0.2)) { model.collapsed.toggle() } }
    }

    /// Фон: стекло/сплошная заливка; за него панель перетаскивается, двойной клик сбрасывает позицию.
    private func background<S: Shape>(_ shape: S) -> some View {
        Group {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
            else { Color.clear.glassEffect(.regular, in: shape) }
        }
        .contentShape(shape)
        .onTapGesture(count: 2, perform: reset)
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in dragChanged() }
            .onEnded { _ in dragEnded() })
    }

    private var expandedBody: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.dashed.inset.filled").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Editing widgets").font(.callout.weight(.semibold))
            Button(action: layout) { Label("Layout…", systemImage: "rectangle.3.group") }
                .buttonStyle(PanelButtonStyle(prominent: false))
                .accessibilityLabel("Layout")
                .accessibilityHint("Opens layout and snapping settings")
                .help("Layout and snapping settings")
            Button(action: done) { Label("Done", systemImage: "checkmark") }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .accessibilityLabel("Done")
                .accessibilityHint("Leaves edit mode")
                .help("Leave edit mode")
            Button(action: toggle) { Image(systemName: "chevron.right.circle").imageScale(.large) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Collapse panel")
                .accessibilityHint("Shrinks the panel to a small Done button")
                .help("Collapse panel")
        }
        .controlSize(.regular)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background { background(Capsule()) }
    }

    private var collapsedBody: some View {
        Button(action: done) {
            Image(systemName: "checkmark").font(.title3.weight(.bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(red: 0.0, green: 0.42, blue: 0.9)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityHint("Leaves edit mode")
        .help("Leave edit mode")
        .overlay(alignment: .topTrailing) {
            Button(action: toggle) {
                Image(systemName: "chevron.left.circle.fill").font(.system(size: 14))
                    .symbolRenderingMode(.palette).foregroundStyle(.primary, .regularMaterial)
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .accessibilityLabel("Expand panel")
            .help("Expand panel")
        }
        .background { background(Circle()).padding(-2) }
        .padding(5)
    }
}

/// Кнопки панели не зависят от активности окна: у nonactivating-панели системные .glass-стили рисуются как отключённые.
private struct PanelButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, prominent: prominent)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var hover = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let blue = Color(red: 0.0, green: 0.42, blue: 0.9)
            let p = configuration.isPressed
            configuration.label
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
                .font(.callout.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 14).frame(minHeight: 28)
                .background(Capsule().fill(prominent ? blue.opacity(p ? 0.75 : (hover ? 1 : 0.92))
                                                     : Color.primary.opacity(p ? 0.28 : (hover ? 0.22 : 0.14))))
                .overlay { if hover { Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1) } }
                .overlay { if focused { Capsule().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-2) } }
                .contentShape(Capsule())
                .scaleEffect(p ? 0.96 : (hover ? 1.05 : 1))
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.35), value: hover)
                .onHover { hover = $0 }
        }
    }
}
