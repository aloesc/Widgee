import AppKit
import Combine
import Layout
import Renderer
import SwiftUI
import WidgeeCore
import WidgetHost

@MainActor
final class InstanceModel: ObservableObject {
    @Published var instance: WidgetInstance
    @Published var isEditing = false
    /// Живая подсказка во время перетаскивания/ресайза («360×170 pt · 2×1 cells», «x, y»); nil, когда жест закончен.
    @Published var hud: String?
    init(_ instance: WidgetInstance) { self.instance = instance }
}

final class DesktopWindow: NSWindow {
    /// Ключевым окно виджета может стать только в режиме редактирования (клавиатурная доступность кнопок);
    /// вне его виджет не перехватывает фокус у других приложений.
    var keyAllowed = false
    override var canBecomeKey: Bool { keyAllowed }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Окна виджетов: без рамки, на уровне рабочего стола, видны на всех Spaces.
@MainActor
final class DesktopWindowController {
    private final class Entry {
        let window: DesktopWindow
        let controller: WidgetController
        let model: InstanceModel
        var occlusionObserver: NSObjectProtocol?
        var stateSub: AnyCancellable?
        init(window: DesktopWindow, controller: WidgetController, model: InstanceModel) {
            self.window = window; self.controller = controller; self.model = model
        }
    }

    private unowned let state: AppState
    private var entries: [UUID: Entry] = [:]
    private var editing = false
    let overlay = LayoutOverlay()
    private var observers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    init(state: AppState) {
        self.state = state
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        })
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAllVisible(false) }
        })
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAllVisible(true) }
        })
    }

    /// Следит за светлой/тёмной темой системы и обновляет `Theme.isDark` у запущенных виджетов.
    func startObservingAppearance() {
        guard appearanceObservation == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshThemes() }
        }
    }

    private func refreshThemes() {
        for e in entries.values {
            let i = e.model.instance
            e.controller.update(size: i.size, sizeClass: i.sizeClass, theme: i.theme(isDark: Self.isDark), settings: i.settings)
        }
    }

    /// Клики проходят сквозь окно, кроме режима редактирования и плашки сбоя (там нужна кнопка).
    private func updateMouse(_ e: Entry) {
        var failed = false
        if case .failed = e.controller.state { failed = true }
        e.window.ignoresMouseEvents = !(editing || failed)
        e.window.keyAllowed = editing
    }

    // MARK: синхронизация

    /// Приводит набор окон в соответствие с экземплярами.
    func sync(_ instances: [WidgetInstance]) {
        let ids = Set(instances.map(\.id))
        for (id, e) in entries where !ids.contains(id) {
            e.controller.stop()
            if let o = e.occlusionObserver { NotificationCenter.default.removeObserver(o) }
            e.window.orderOut(nil)
            e.window.contentView = nil
            entries[id] = nil
        }
        for inst in instances where entries[inst.id] == nil { create(inst) }
    }

    private func create(_ inst: WidgetInstance) {
        guard let catalogEntry = state.catalog.entry(inst.widgetID) else {
            AppState.logger.error("widget \(inst.widgetID, privacy: .public) not found, window not created")
            return
        }
        let controller = WidgetController(directory: catalogEntry.directory, metrics: state.metrics, logger: AppState.log)
        let model = InstanceModel(inst)
        model.isEditing = editing

        let window = DesktopWindow(contentRect: frame(for: inst), styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = !editing

        let id = inst.id
        let actions = InstanceActions(
            resize: { [weak state] p in state?.resize(id, to: p) },
            remove: { [weak state] in state?.remove(id) },
            openSettings: { [weak state] in state?.openSettings(id) },
            dragMove: { [weak self] p, opt in self?.dragMove(id, to: p, optionHeld: opt) },
            dragEnd: { [weak self] opt in self?.dragEnd(id, optionHeld: opt) },
            resizeMove: { [weak self] s, opt in self?.resizeMove(id, size: s, optionHeld: opt) },
            resizeEnd: { [weak self] in self?.resizeEnd(id) },
            restart: { [weak controller] in Task { await controller?.restart() } })
        let view = WidgetInstanceView(model: model, controller: controller, allowedSizes: Set(catalogEntry.manifest.sizes),
                                      actions: actions)
        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(frame(for: inst), display: false)
        window.orderFrontRegardless()

        let entry = Entry(window: window, controller: controller, model: model)
        entry.occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak controller, weak window] _ in
            MainActor.assumeIsolated {
                if let w = window { controller?.setVisible(w.occlusionState.contains(.visible)) }
            }
        }
        entries[inst.id] = entry
        entry.stateSub = controller.$state.receive(on: DispatchQueue.main).sink { [weak self, weak entry] _ in
            MainActor.assumeIsolated { if let self, let entry { self.updateMouse(entry) } }
        }

        let size = inst.size, sc = inst.sizeClass, theme = inst.theme(isDark: Self.isDark), settings = inst.settings
        Task { await controller.start(size: size, sizeClass: sc, theme: theme, settings: settings) }
    }

    func apply(_ inst: WidgetInstance) {
        guard let e = entries[inst.id] else { return }
        let old = e.model.instance
        e.model.instance = inst
        e.window.setFrame(frame(for: inst), display: true)
        let theme = inst.theme(isDark: Self.isDark)
        if old.size != inst.size || old.sizeClass != inst.sizeClass || old.settings != inst.settings
            || old.theme(isDark: Self.isDark) != theme {
            e.controller.update(size: inst.size, sizeClass: inst.sizeClass, theme: theme, settings: inst.settings)
        }
    }

    func setEditing(_ value: Bool) {
        editing = value
        for e in entries.values { e.model.isEditing = value; updateMouse(e) }
        overlay.setGuides([], on: nil)
        overlay.refresh(editing: editing, layout: state.layout)
    }

    /// Выводит окно виджета наверх среди виджетов и коротко мигает им, чтобы найти его на рабочем столе.
    func flash(_ id: UUID) {
        guard let w = entries[id]?.window else { return }
        w.orderFrontRegardless()
        Task { @MainActor [weak w] in
            for _ in 0..<3 {
                for a in [0.15, 1.0] as [CGFloat] {
                    guard let w else { return }
                    NSAnimationContext.beginGrouping()
                    NSAnimationContext.current.duration = 0.18
                    w.animator().alphaValue = a
                    NSAnimationContext.endGrouping()
                    try? await Task.sleep(for: .milliseconds(220))
                }
            }
            w?.alphaValue = 1
        }
    }

    func currentFrame(of id: UUID) -> NSRect? { entries[id]?.window.frame }

    private func setAllVisible(_ v: Bool) {
        for e in entries.values { e.controller.setVisible(v && e.window.occlusionState.contains(.visible)) }
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: геометрия

    /// Главный монитор — первый в `NSScreen.screens` (с меню-баром).
    private static var primaryScreen: NSScreen? { NSScreen.screens.first }

    /// Окно целиком в пределах экрана экземпляра. Нет экрана -> главный; сохранённая позиция не меняется.
    private func frame(for inst: WidgetInstance) -> NSRect {
        let screen = NSScreen.screens.first { $0.displayID != nil && $0.displayID == inst.displayID }
            ?? Self.primaryScreen
        let sf = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxX = max(sf.minX, sf.maxX - inst.width)
        let maxY = max(sf.minY, sf.maxY - inst.height)
        let x = min(max(sf.minX + inst.offsetX, sf.minX), maxX)
        let y = min(max(sf.minY + inst.offsetY, sf.minY), maxY)
        return NSRect(x: x, y: y, width: inst.width, height: inst.height)
    }

    /// Экран с наибольшим пересечением и смещение окна от его левого нижнего угла.
    static func position(for frame: NSRect) -> (displayID: UInt32?, x: Double, y: Double) {
        let best = NSScreen.screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? primaryScreen
        guard let s = best else { return (nil, frame.minX, frame.minY) }
        return (s.displayID, frame.minX - s.frame.minX, frame.minY - s.frame.minY)
    }

    // MARK: прилипание, сетка, ресайз

    var debugWidgetFrames: [NSRect] { entries.values.map { $0.window.frame } }

    func layoutChanged() { overlay.refresh(editing: editing, layout: state.layout) }

    private func screen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area } ?? Self.primaryScreen
    }

    private func othersFrames(excluding id: UUID, on s: NSScreen) -> [CGRect] {
        entries.filter { $0.key != id && screen(for: $0.value.window.frame) == s }.map { $0.value.window.frame }
    }

    private func grid(on s: NSScreen) -> SnapGridLayout? {
        let g = SnapGridLayout(screen: s.visibleFrame, settings: state.layout.grid)
        return state.layout.grid.enabled && g.cellWidth > 0 && g.cellHeight > 0 ? g : nil
    }

    /// Прямоугольник пресета в ячейках сетки (левый верхний угол — ближайшая ячейка); nil при выключенной сетке.
    func gridRect(for current: NSRect, preset: WidgetSizePreset) -> NSRect? {
        guard let s = screen(for: current), let g = grid(on: s),
              let gp = GridSizePreset(rawValue: preset.rawValue) else { return nil }
        let sp = SnapGridLayout.spans(for: gp, columns: g.columns, rows: g.rows)
        let o = g.snapOrigin(for: current)
        return g.rect(forSpan: GridSpan(columns: sp.cols, rows: sp.rows), at: GridCell(column: o.col, row: o.row))
    }

    /// Перетаскивание: позиция корректируется движком прилипания, направляющие рисует оверлей.
    func dragMove(_ id: UUID, to origin: NSPoint, optionHeld: Bool) {
        guard let e = entries[id] else { return }
        defer { e.model.hud = "\(Int(e.window.frame.minX)), \(Int(e.window.frame.minY))" }
        let proposed = NSRect(origin: origin, size: e.window.frame.size)
        guard let s = screen(for: proposed) else { e.window.setFrameOrigin(origin); return }
        let r = SnapEngine.snap(moving: proposed, others: othersFrames(excluding: id, on: s), screen: s.visibleFrame,
                                settings: state.layout, disabled: optionHeld)
        e.window.setFrameOrigin(r.rect.origin)
        overlay.setGuides(r.guides, on: s)
        overlay.refresh(editing: editing, layout: state.layout)
    }

    func dragEnd(_ id: UUID, optionHeld: Bool) {
        guard let e = entries[id] else { return }
        e.model.hud = nil
        overlay.setGuides([], on: nil)
        var f = e.window.frame
        if !optionHeld, let s = screen(for: f), let g = grid(on: s) { f = g.snapped(f) }
        commit(id, f)
        overlay.refresh(editing: editing, layout: state.layout)
    }

    /// Свободный ресайз: левый верхний угол на месте, содержимое перерисовывается на лету.
    func resizeMove(_ id: UUID, size: CGSize, optionHeld: Bool) {
        guard let e = entries[id] else { return }
        defer {
            let sz = e.window.frame.size
            e.model.hud = "\(Int(sz.width))×\(Int(sz.height)) pt · \(WidgetSizePreset.nearest(to: sz).cellLabel) cells"
        }
        let cur = e.window.frame
        guard let s = screen(for: cur) else { return }
        let vis = s.visibleFrame
        // Верх-лево фиксирован: правый/нижний край не уходят за видимую область экрана.
        let maxW = max(120, vis.maxX - cur.minX), maxH = max(80, cur.maxY - vis.minY)
        let w = min(max(size.width, 120), maxW), h = min(max(size.height, 80), maxH)
        var rect = NSRect(x: cur.minX, y: cur.maxY - h, width: w, height: h)
        var guides: [Guide] = []
        if !optionHeld, let g = grid(on: s) {
            rect = g.snapped(rect)
        } else {
            // Двигается только правый нижний угол: снапим точку-угол теми же правилами.
            let corner = CGRect(x: rect.maxX, y: rect.minY, width: 0, height: 0)
            let r = SnapEngine.snap(moving: corner, others: othersFrames(excluding: id, on: s), screen: vis,
                                    settings: state.layout, disabled: optionHeld)
            let nw = min(max(w + (r.rect.minX - corner.minX), 120), maxW)
            let nh = min(max(h - (r.rect.minY - corner.minY), 80), maxH)
            rect = NSRect(x: cur.minX, y: cur.maxY - nh, width: nw, height: nh)
            guides = r.guides
        }
        applyLive(e, rect)
        overlay.setGuides(guides, on: s)
        overlay.refresh(editing: editing, layout: state.layout)
    }

    func resizeEnd(_ id: UUID) {
        guard let e = entries[id] else { return }
        e.model.hud = nil
        overlay.setGuides([], on: nil)
        commit(id, e.window.frame)
        overlay.refresh(editing: editing, layout: state.layout)
    }

    private func applyLive(_ e: Entry, _ rect: NSRect) {
        e.window.setFrame(rect, display: true)
        var inst = e.model.instance
        guard abs(inst.width - rect.width) > 0.1 || abs(inst.height - rect.height) > 0.1 else { return }
        inst.width = rect.width; inst.height = rect.height
        inst.sizeClass = WidgetSizePreset.nearest(to: rect.size).sizeClass
        e.model.instance = inst
        e.controller.update(size: inst.size, sizeClass: inst.sizeClass, theme: inst.theme(isDark: Self.isDark), settings: inst.settings)
    }

    /// Сохраняет итоговую рамку окна (позиция и, если изменился, размер) в конфиг.
    private func commit(_ id: UUID, _ f: NSRect) {
        let pos = Self.position(for: f)
        state.update(id) {
            if abs($0.width - f.width) > 0.5 || abs($0.height - f.height) > 0.5 {
                $0.sizeClass = WidgetSizePreset.nearest(to: f.size).sizeClass
            }
            $0.width = f.width; $0.height = f.height
            $0.displayID = pos.displayID; $0.offsetX = pos.x; $0.offsetY = pos.y
        }
    }

    /// Смена экранов: окна переезжают на главный монитор или возвращаются на свой.
    func relayout() {
        for e in entries.values { e.window.setFrame(frame(for: e.model.instance), display: true) }
    }
}

private extension NSRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
