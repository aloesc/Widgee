import Metrics
import SwiftUI
import WidgeeCore
import WidgetHost
import Renderer
import Background

/// Открыто ли окно галереи: при закрытии превью останавливают опросы.
@MainActor
final class GalleryActivity: ObservableObject {
    @Published var isOpen = false
}

struct GalleryItem: Identifiable, Equatable {
    let id: String
    let entry: CatalogEntry
    let variant: String
    var preset: WidgetSizePreset
    let settings: [String: JSONValue]
    var title: String { entry.manifest.name }
}

enum GalleryCategory: String, CaseIterable, Identifiable {
    case all = "All Widgets", today = "Today", weather = "Weather", battery = "Battery", clock = "Clock", system = "System", other = "Other"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .today: "calendar"
        case .weather: "cloud.sun.fill"
        case .battery: "battery.100percent"
        case .clock: "clock.fill"
        case .system: "cpu"
        case .other: "ellipsis"
        }
    }
    /// Категория для показа виджета в группах «All Widgets».
    static func of(_ e: CatalogEntry) -> GalleryCategory {
        switch e.category {
        case "weather": .weather
        case "battery": .battery
        case "clock": .clock
        case "system": .system
        case "today": .today
        default: .other
        }
    }
    func matches(_ e: CatalogEntry) -> Bool {
        switch self {
        case .all: true
        case .today: ["today", "clock", "weather"].contains(e.category)
        case .weather: e.category == "weather"
        case .battery: e.category == "battery"
        case .clock: e.category == "clock"
        case .system: e.category == "system"
        case .other: !["clock", "battery", "today", "weather", "system"].contains(e.category)
        }
    }
}

/// Запрос выбрать вариант в галерее (отладочный флаг `--select-widget`).
struct GalleryRequest: Equatable {
    var key: String
    var preset: WidgetSizePreset?
}

enum MainSection: String, CaseIterable, Identifiable {
    case gallery, mine, create, layout, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .mine: "My Widgets"
        case .create: "Create Widget"
        case .layout: "Layout"
        case .settings: "Settings"
        }
    }
    var subtitle: String {
        switch self {
        case .gallery: "Useful information right on your desktop."
        case .mine: "Widgets placed on your desktop."
        case .create: "Describe a widget and let your AI agent build it."
        case .layout: "Snapping and grid for widgets on the desktop."
        case .settings: "Startup, shortcuts and information about Widgee."
        }
    }
    var symbol: String {
        switch self {
        case .gallery: "square.grid.2x2.fill"
        case .mine: "square.grid.2x2"
        case .create: "sparkles"
        case .layout: "rectangle.3.group"
        case .settings: "gearshape.fill"
        }
    }
}

enum SidebarItem: Hashable {
    case category(GalleryCategory)
    case section(MainSection)
}

/// Главное окно: NavigationSplitView с боковой панелью, тулбаром и поиском.
struct MainWindowView: View {
    @ObservedObject var state: AppState
    @ObservedObject var catalog: WidgetCatalog
    @State private var search = ""

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { state.section == .gallery ? .category(state.galleryCategory) : .section(state.section) },
            set: { item in
                switch item {
                case .category(let c): state.galleryCategory = c; state.section = .gallery
                case .section(let s): state.section = s
                case nil: break
                }
            })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search widgets")
        .onChange(of: search) { if !search.isEmpty { state.section = .gallery } }
        // Если выбранная категория опустела (например, удалили пользовательский виджет), возвращаемся к All Widgets.
        .onChange(of: catalog.entries.count) {
            let c = state.galleryCategory
            if c != .all, !catalog.entries.contains(where: { c.matches($0) }) { state.galleryCategory = .all }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $state.isEditing) {
                    Label("Edit Mode", systemImage: state.isEditing ? "pencil.and.ruler.fill" : "pencil.and.ruler")
                }
                .toggleStyle(.button)
                .help("Edit Mode: move and resize widgets on the desktop")
                .accessibilityLabel("Edit Mode")
                .accessibilityHint("Turns on moving and resizing of widgets on the desktop")
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { try? FileManager.default.createDirectory(at: ConfigStore.userWidgetsDirectory, withIntermediateDirectories: true) }
    }

    @ViewBuilder private var detail: some View {
        switch state.section {
        case .gallery:
            GalleryView(state: state, catalog: catalog, search: search, category: state.galleryCategory)
        case .mine:
            page(.mine) { MyWidgetsView(state: state) }
        case .create:
            page(.create) {
                CreateWidgetView(widgetsDirectory: ConfigStore.userWidgetsDirectory,
                                 openFolder: { state.openWidgetsFolder() })
            }
        case .layout:
            page(.layout) { LayoutSettingsView(state: state) }
        case .settings:
            page(.settings) { SettingsView(state: state, launch: state.launch) }
        }
    }

    private func page<C: View>(_ s: MainSection, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: s.title, subtitle: s.subtitle)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: боковая панель

    private var sidebar: some View {
        List(selection: selection) {
            Section("Gallery") {
                ForEach(GalleryCategory.allCases) { c in
                    let n = c == .all ? catalog.entries.count : catalog.entries.filter(c.matches).count
                    if c == .all || n > 0 {
                    row(c.symbol, c.rawValue, tint: c.tint, count: n)
                        .tag(SidebarItem.category(c))
                    }
                }
            }
            Section("Widgee") {
                ForEach([MainSection.mine, .create, .layout, .settings]) { s in
                    row(s.symbol, s.title, tint: s.tint, count: s == .mine ? state.instances.count : nil)
                        .tag(SidebarItem.section(s))
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Sections")
    }

    private func row(_ symbol: String, _ title: String, tint: Color, count: Int?) -> some View {
        HStack(spacing: DS.Space.xs) {
            SidebarIcon(symbol: symbol, tint: tint)
            Text(title).font(.dsBody)
            Spacer(minLength: 0)
            if let count { Text("\(count)").font(.dsCaption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }
}

struct GalleryView: View {
    @ObservedObject var state: AppState
    @ObservedObject var catalog: WidgetCatalog
    let search: String
    let category: GalleryCategory
    @State private var selectedID: String?
    @State private var heroPreset: WidgetSizePreset?
    @State private var justAdded = false
    @State private var lastAdded: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [(GalleryCategory, [GalleryItem])] {
        var byCat: [GalleryCategory: [GalleryItem]] = [:]
        for e in catalog.entries where category.matches(e) {
            var vs = Self.variants(for: e)
            if !search.isEmpty {
                vs = vs.filter {
                    $0.title.localizedCaseInsensitiveContains(search) || $0.variant.localizedCaseInsensitiveContains(search)
                        || $0.entry.description.localizedCaseInsensitiveContains(search)
                }
            }
            byCat[category == .all ? GalleryCategory.of(e) : category, default: []] += vs
        }
        return GalleryCategory.allCases.compactMap { c in byCat[c].map { (c, $0) } }
    }

    var body: some View {
        let gs = groups
        let list = gs.flatMap(\.1)
        let selected = list.first { $0.id == selectedID } ?? list.first
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    SectionHeader(title: category == .all ? "Widgets" : category.rawValue,
                                  subtitle: "Useful information right on your desktop.")
                    if list.isEmpty {
                        empty
                    } else {
                        if let selected { hero(selected).id("hero") }
                        ForEach(gs, id: \.0) { cat, items in
                            VStack(alignment: .leading, spacing: DS.Space.s) {
                                if category == .all {
                                    GroupHeader(title: cat.rawValue, symbol: cat.symbol, tint: cat.tint, count: items.count)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: DS.Space.m, alignment: .top)],
                                          alignment: .leading, spacing: DS.Space.m) {
                                    ForEach(items) { item in
                                        tile(item, isSelected: item.id == selected?.id) {
                                            select(item)
                                            withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo("hero", anchor: .top) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.l)
            }
        }
        .onAppear(perform: applyRequest)
        .onChange(of: state.galleryRequest) { applyRequest() }
    }

    private var empty: some View {
        Group {
            if search.isEmpty {
                ContentUnavailableView("No Widgets", systemImage: "square.dashed", description: Text("Nothing in this category yet."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func select(_ item: GalleryItem) {
        selectedID = item.id
        heroPreset = nil
        justAdded = false
        lastAdded = nil
    }

    private func applyRequest() {
        guard let r = state.galleryRequest else { return }
        let all = catalog.entries.flatMap { Self.variants(for: $0) }
        let match = Int(r.key).flatMap { all.indices.contains($0) ? all[$0] : nil }
            ?? all.first { $0.id == r.key } ?? all.first { $0.entry.id == r.key }
        if let match { selectedID = match.id; heroPreset = r.preset }
        state.galleryRequest = nil
    }

    private func add(_ item: GalleryItem, preset: WidgetSizePreset) {
        state.addWidget(item.entry, preset: preset, settings: item.settings)
        lastAdded = state.instances.last?.id
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { justAdded = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { justAdded = false }
        }
    }

    private static func isAvailable(_ item: GalleryItem, _ p: WidgetSizePreset) -> Bool {
        let sizes = item.entry.manifest.sizes
        return sizes.isEmpty || sizes.contains(p.rawValue)
    }

    // MARK: hero

    private func hero(_ base: GalleryItem) -> some View {
        var item = base
        item.preset = heroPreset ?? base.preset
        let cat = GalleryCategory.of(base.entry)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Space.l) {
                desk(item).frame(minWidth: 440, maxWidth: 580)
                info(item, cat: cat).frame(width: 280)
            }
            VStack(alignment: .leading, spacing: DS.Space.m) {
                desk(item).frame(maxWidth: 560)
                info(item, cat: cat)
            }
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.xlarge, style: .continuous).fill(cat.tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xlarge, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected widget: \(item.title), \(item.variant)")
    }

    private func desk(_ item: GalleryItem) -> some View {
        MiniDesktop { scale in
            WidgetPreview(item: item, maxSize: CGSize(width: 800, height: 400), metrics: state.metrics, scale: scale)
                .id(item.id)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        }
    }

    private func info(_ item: GalleryItem, cat: GalleryCategory) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xs) {
                Text(item.title).font(.dsTitle)
                Chip(text: item.variant, tint: cat.tint)
            }
            Text(item.entry.description.isEmpty ? "A widget for your desktop." : item.entry.description)
                .font(.dsBody).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !item.entry.isBuiltin {
                Text("Author: \(item.entry.manifest.author) · v\(item.entry.manifest.version)")
                    .font(.dsCaption).foregroundStyle(.secondary)
            }
            Text("Size").font(.dsCaption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, DS.Space.xxs)
            HStack(spacing: DS.Space.xs) {
                ForEach(WidgetSizePreset.allCases, id: \.self) { p in
                    sizeButton(p, item: item, tint: cat.tint)
                }
            }
            Spacer(minLength: DS.Space.xs)
            HStack(spacing: DS.Space.xs) {
                if justAdded {
                    Label("Added", systemImage: "checkmark")
                        .font(.dsBody.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.m).frame(minHeight: 32)
                        .background(Capsule().fill(Color.green))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Added to desktop")
                } else {
                    Button { add(item, preset: item.preset) } label: { Label("Add to Desktop", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityHint("Places this widget on the desktop in the selected size")
                }
                if let id = lastAdded, state.instance(id) != nil {
                    Button("Show on desktop") { state.desktop.flash(id) }
                        .buttonStyle(.widgeeSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sizeButton(_ p: WidgetSizePreset, item: GalleryItem, tint: Color) -> some View {
        let on = item.preset == p
        let ok = Self.isAvailable(item, p)
        return Button {
            heroPreset = p
        } label: {
            Text(p.cellLabel)
                .font(.dsCaption.weight(.semibold).monospacedDigit())
                .foregroundStyle(on ? Color.white : (ok ? Color.primary : Color.secondary))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? tint : Color.primary.opacity(ok ? 0.1 : 0.04)))
                .opacity(ok ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!ok)
        .accessibilityLabel("\(p.cells.cols) by \(p.cells.rows)")
        .accessibilityHint(ok ? "Previews this size" : "Not available for this widget")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: плитки

    private func tile(_ item: GalleryItem, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        let cat = GalleryCategory.of(item.entry)
        return GlassCard(selected: isSelected, radius: DS.Radius.large) {
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [cat.tint.opacity(0.32), cat.tint.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    WidgetPreview(item: item, maxSize: CGSize(width: 190, height: 110), metrics: state.metrics)
                        .id(item.id)
                }
                .frame(height: 140)
                HStack(alignment: .center, spacing: DS.Space.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.dsBody.weight(.semibold)).lineLimit(1)
                        HStack(spacing: DS.Space.xs) {
                            Text(item.variant).font(.dsCaption).foregroundStyle(.secondary).lineLimit(1)
                            Badge(text: item.preset.cellLabel)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { add(item, preset: item.preset) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 22)).symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .help("Add to Desktop")
                    .accessibilityLabel("Add \(item.title), \(item.variant), to desktop")
                }
                .padding(DS.Space.s)
            }
        }
        .onTapGesture(count: 2) { onSelect(); add(item, preset: item.preset) }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title), \(item.variant), \(item.preset.cellLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Select") { onSelect() }
    }

    // MARK: варианты

    static func variants(for e: CatalogEntry) -> [GalleryItem] {
        func v(_ key: String, _ name: String, _ p: WidgetSizePreset, _ s: [String: JSONValue]) -> GalleryItem {
            GalleryItem(id: "\(e.id)/\(key)", entry: e, variant: name, preset: p, settings: s)
        }
        // Варианты задаются в manifest.json (`variants`); без них — одна карточка с настройками по умолчанию.
        let declared = e.manifest.variants.compactMap { x -> GalleryItem? in
            guard let p = WidgetSizePreset(rawValue: x.size) else { return nil }
            return v(x.key, x.name, p, x.settings)
        }
        if !declared.isEmpty { return declared }
        return [v("default", e.manifest.version, e.defaultPreset, [:])]
    }
}

/// Живое превью виджета, уменьшенное до `maxSize`.
struct WidgetPreview: View {
    let item: GalleryItem
    let maxSize: CGSize
    var fixedScale: CGFloat?
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller: WidgetController
    @EnvironmentObject private var activity: GalleryActivity

    init(item: GalleryItem, maxSize: CGSize, metrics: MetricsProvider, scale: CGFloat? = nil) {
        self.item = item
        self.maxSize = maxSize
        self.fixedScale = scale
        _controller = StateObject(wrappedValue: WidgetController(
            directory: item.entry.directory, metrics: metrics, logger: AppState.log))
    }

    var body: some View {
        let size = item.preset.size
        let scale = fixedScale ?? min(maxSize.width / size.width, maxSize.height / size.height, 1)
        let theme = Theme()
        Group {
            if case .failed = controller.state {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if let tree = controller.tree {
                WidgetTreeView(node: tree, theme: theme, sizeClass: item.preset.sizeClass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .widgetBackground(item.entry.defaultBackground ?? .liquidGlass, cornerRadius: theme.cornerRadius)
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: item.preset)
        .onAppear { visible = true }
        .onChange(of: item.preset) {
            guard activity.isOpen, visible else { return }
            controller.update(size: item.preset.size, sizeClass: item.preset.sizeClass, theme: theme,
                              settings: item.entry.defaultSettings.merging(item.settings) { _, n in n })
        }
        .task(id: activity.isOpen && visible) {
            guard activity.isOpen, visible else { controller.stop(); return }
            await controller.start(size: size, sizeClass: item.preset.sizeClass, theme: theme,
                                   settings: item.entry.defaultSettings.merging(item.settings) { _, n in n })
        }
        .onDisappear { visible = false; controller.stop() }
    }
}

