import AppKit
import Layout
import Metrics
import OSLog
import SwiftUI
import WidgeeCore
import WidgetHost

/// Единая точка состояния приложения: экземпляры виджетов, режим редактирования, окна.
@MainActor
final class AppState: ObservableObject {
    static let logger = Logger(subsystem: "io.github.aloesc.macoswidgets", category: "app")
    static let log: @Sendable (String) -> Void = { msg in
        Logger(subsystem: "io.github.aloesc.macoswidgets", category: "widget").info("\(msg, privacy: .public)")
    }

    @Published private(set) var instances: [WidgetInstance] = []
    /// Раздел главного окна; открытие из меню/флагов переключает его.
    @Published var section: MainSection = .gallery
    @Published var galleryCategory: GalleryCategory = .all
    @Published var galleryRequest: GalleryRequest?
    let launch = LaunchAtLogin()
    @Published var isEditing = false {
        didSet { desktop.setEditing(isEditing); editPanel?.setVisible(isEditing) }
    }

    /// Живые настройки раскладки: сохраняются и применяются сразу.
    @Published var layout = LayoutSettings() {
        didSet {
            guard oldValue != layout else { return }
            desktop?.layoutChanged()
            if configLoaded { save() }
        }
    }
    private var configLoaded = false

    let store: ConfigStore
    let catalog = WidgetCatalog(log: AppState.log)
    private var catalogWatcher: CatalogWatcher?
    let metrics = MetricsProvider()
    private(set) var desktop: DesktopWindowController!
    private(set) var windows: AuxWindows!
    private(set) var editPanel: EditPanelController!

    init(store: ConfigStore = .default) {
        self.store = store
        self.desktop = DesktopWindowController(state: self)
        self.windows = AuxWindows(state: self)
        self.editPanel = EditPanelController(state: self)
    }

    func bootstrap() {
        try? FileManager.default.createDirectory(at: ConfigStore.userWidgetsDirectory, withIntermediateDirectories: true)
        catalog.reload()
        catalogWatcher = CatalogWatcher(directory: ConfigStore.userWidgetsDirectory) { [weak self] in
            MainActor.assumeIsolated { self?.catalog.reload() }
        }
        let isFirstLaunch = !FileManager.default.fileExists(atPath: store.url.path)
        let loaded = store.load(log: { Self.logger.error("\($0, privacy: .public)") })
        instances = loaded.instances
        layout = loaded.layout
        configLoaded = true
        desktop.sync(instances)
        // Первый запуск: пустой рабочий стол, галерея сразу открыта, чтобы пользователь выбрал виджеты сам.
        if isFirstLaunch { openGallery() }
    }

    func instance(_ id: UUID) -> WidgetInstance? { instances.first { $0.id == id } }

    func addWidget(_ entry: CatalogEntry, preset: WidgetSizePreset, settings: [String: JSONValue]) {
        guard let screen = NSScreen.screens.first else { return }
        let n = Double(instances.count % 8) * 28
        var inst = WidgetInstance(
            widgetID: entry.id, preset: preset,
            displayID: screen.displayID,
            offsetX: 80 + n,
            offsetY: max(0, screen.frame.height - preset.size.height - 120 - n),
            settings: entry.defaultSettings.merging(settings) { _, new in new })
        inst.accentHex = "#0A84FF"
        if let bg = entry.defaultBackground { inst.background = bg }
        instances.append(inst)
        save()
        desktop.sync(instances)
    }

    func update(_ id: UUID, _ mutate: (inout WidgetInstance) -> Void) {
        guard let i = instances.firstIndex(where: { $0.id == id }) else { return }
        mutate(&instances[i])
        save()
        desktop.apply(instances[i])
    }

    func resize(_ id: UUID, to preset: WidgetSizePreset) {
        guard let current = desktop.currentFrame(of: id) else { return }
        // Левый верхний угол остаётся на месте.
        var new = NSRect(x: current.minX, y: current.maxY - preset.size.height,
                         width: preset.size.width, height: preset.size.height)
        // Сетка включена: размер = спан пресета в ячейках, виджет вписывается в ячейки.
        if let g = desktop.gridRect(for: current, preset: preset) { new = g }
        let pos = DesktopWindowController.position(for: new)
        update(id) {
            $0.apply(preset: preset)
            $0.width = new.width; $0.height = new.height
            $0.displayID = pos.displayID; $0.offsetX = pos.x; $0.offsetY = pos.y
        }
    }

    func remove(_ id: UUID) {
        instances.removeAll { $0.id == id }
        save()
        windows.closeSettings(id)
        desktop.sync(instances)
    }

    func save() {
        do { try store.save(AppConfig(instances: instances, layout: layout)) }
        catch { Self.logger.error("failed to save config.json: \(error.localizedDescription, privacy: .public)") }
    }

    func openSection(_ s: MainSection) {
        if s == .gallery { catalog.reload() }
        section = s
        windows.showMain()
    }
    func openGallery() { openSection(.gallery) }
    func openCreate() { openSection(.create) }
    func openAbout() { openSection(.settings) }
    func openLayout() { openSection(.layout) }
    func openSettings(_ id: UUID) { windows.showSettings(id) }

    func openWidgetsFolder() {
        let dir = ConfigStore.userWidgetsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension Color {
    /// `#RRGGBB` в sRGB.
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func b(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }
}

extension WidgetInstance {
    /// Системная схема `isDark` с учётом принудительного Light/Dark.
    func resolvedIsDark(_ isDark: Bool) -> Bool {
        switch textAppearance ?? .auto { case .auto: isDark; case .light: false; case .dark: true }
    }

    func theme(isDark: Bool) -> Theme {
        Theme(cornerRadius: cornerRadius, fontDesign: fontDesign, accentHex: accentHex, isDark: resolvedIsDark(isDark),
              alignment: alignment ?? .auto)
    }
}
