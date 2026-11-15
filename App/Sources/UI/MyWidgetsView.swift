import SwiftUI
import WidgeeCore
import WidgetHost
import Renderer
import Background
import Metrics

/// Подложка карточек превью: обои или градиент (чтобы стекло выглядело естественно).
struct CardBackdrop: View {
    @ObservedObject private var wallpaper = WallpaperProvider.shared
    var body: some View {
        Group {
            if let img = wallpaper.image {
                Color.clear.overlay { Image(nsImage: img).resizable().scaledToFill() }.clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.62, green: 0.38, blue: 0.9),
                                        Color(red: 0.95, green: 0.55, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .onAppear { wallpaper.loadIfNeeded() }
    }
}

/// «My Widgets»: карта рабочего стола, карточки живых превью и панель настроек выбранного виджета.
struct MyWidgetsView: View {
    @ObservedObject var state: AppState
    @State private var selectedID: UUID?
    @State private var confirmRemove = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let list = state.instances
        let selected = list.first { $0.id == selectedID } ?? list.first
        if list.isEmpty {
            EmptyStateView(symbol: "square.grid.2x2", title: "No widgets yet",
                           message: "Pick a widget in the gallery and it will appear on your desktop.", tint: MainSection.mine.tint) {
                Button { state.section = .gallery } label: { Label("Browse Gallery", systemImage: "square.grid.2x2.fill") }
                    .buttonStyle(.widgeePrimary).controlSize(.large)
            }
        } else {
            HStack(alignment: .top, spacing: DS.Space.l) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            GroupHeader(title: "Desktop map", symbol: "display", tint: MainSection.mine.tint)
                            desktopMap(list, selected: selected)
                        }
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            GroupHeader(title: "Placed widgets", symbol: "square.grid.2x2", tint: MainSection.mine.tint, count: list.count)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: DS.Space.m, alignment: .top)],
                                      alignment: .leading, spacing: DS.Space.m) {
                                ForEach(list) { inst in
                                    Button { selectedID = inst.id } label: { card(inst, isSelected: inst.id == selected?.id) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.xs).padding(.bottom, DS.Space.l)
                }
                .scrollClipDisabled()
                if let selected { panel(selected).frame(width: 340) }
            }
        }
    }

    private func title(_ inst: WidgetInstance) -> String {
        state.catalog.entry(inst.widgetID)?.manifest.name ?? inst.widgetID
    }

    private func backgroundInfo(_ inst: WidgetInstance) -> (name: String, symbol: String) {
        switch inst.background {
        case .liquidGlass: ("Liquid Glass", "drop.fill")
        case .clear: ("Clear", "circle.dashed")
        case .color: ("Color", "paintpalette.fill")
        case .tint: ("Tint", "paintbrush.fill")
        }
    }

    // MARK: карта рабочего стола

    private func desktopMap(_ list: [WidgetInstance], selected: WidgetInstance?) -> some View {
        let screen = NSScreen.screens.first
        let size = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let onMain = list.filter { $0.displayID == nil || $0.displayID == screen?.displayID }
        return MiniDesktop { _ in EmptyView() }
            .overlay {
                GeometryReader { geo in
                    let k = geo.size.width / size.width
                    ForEach(onMain) { inst in
                        let w = inst.width * k, h = inst.height * k
                        let x = inst.offsetX * k, y = (size.height - inst.offsetY - inst.height) * k * (geo.size.height / (size.height * k))
                        mapWidget(inst, selected: inst.id == selected?.id, w: w, h: h)
                            .position(x: x + w / 2, y: y + h / 2)
                    }
                }
            }
            .frame(maxWidth: 640)
    }

    private func mapWidget(_ inst: WidgetInstance, selected: Bool, w: CGFloat, h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(3, min(w, h) * 0.2), style: .continuous)
        return shape
            .fill(selected ? AnyShapeStyle(DS.accent.opacity(0.6)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(shape.strokeBorder(selected ? Color.white : Color.white.opacity(0.45), lineWidth: selected ? 2.5 : 1))
            .overlay {
                if w > 44 {
                    Text(title(inst)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 1).padding(3)
                }
            }
            .shadow(color: selected ? DS.accent.opacity(0.8) : .black.opacity(0.25), radius: selected ? 8 : 3)
            .frame(width: w, height: h)
            .contentShape(shape)
            .onTapGesture { selectedID = inst.id }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title(inst)) on desktop map")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: карточка

    private func card(_ inst: WidgetInstance, isSelected: Bool) -> some View {
        let bg = backgroundInfo(inst)
        return GlassCard(selected: isSelected, tint: DS.accent) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ZStack {
                    CardBackdrop()
                    if let entry = state.catalog.entry(inst.widgetID) {
                        InstancePreview(instance: inst, entry: entry, maxSize: CGSize(width: 180, height: 120), metrics: state.metrics)
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
                Text(title(inst)).font(.headline).lineLimit(1)
                HStack(spacing: DS.Space.xs) {
                    Badge(text: WidgetSizePreset.nearest(to: inst.size).cellLabel)
                    Chip(text: bg.name, tint: .secondary, symbol: bg.symbol)
                    Spacer(minLength: 0)
                }
            }
            .padding(DS.Space.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title(inst)), \(WidgetSizePreset.nearest(to: inst.size).cellLabel) cells, \(bg.name) background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: панель настроек

    private func panel(_ inst: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title(inst)).font(.dsTitle).lineLimit(1)
                HStack(spacing: DS.Space.xs) {
                    Badge(text: WidgetSizePreset.nearest(to: inst.size).cellLabel)
                    Text("\(Int(inst.width))×\(Int(inst.height)) pt").font(.dsCaption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: DS.Space.xs) {
                Button { state.desktop.flash(inst.id) } label: { Label("Show on desktop", systemImage: "scope") }
                    .buttonStyle(.widgeeSecondary)
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmRemove = true } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(DestructiveButtonStyle())
            }
            InstanceSettingsView(state: state, id: inst.id)
        }
        .confirmationDialog("Remove this widget?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { state.remove(inst.id) }
        } message: { Text("\(title(inst)) will be removed from the desktop.") }
    }
}

/// Живое превью размещённого экземпляра; работает, пока плитка видна и окно открыто.
struct InstancePreview: View {
    let instance: WidgetInstance
    let entry: CatalogEntry
    let maxSize: CGSize
    @StateObject private var controller: WidgetController
    @EnvironmentObject private var activity: GalleryActivity
    @Environment(\.colorScheme) private var colorScheme

    init(instance: WidgetInstance, entry: CatalogEntry, maxSize: CGSize, metrics: MetricsProvider) {
        self.instance = instance
        self.entry = entry
        self.maxSize = maxSize
        _controller = StateObject(wrappedValue: WidgetController(
            directory: entry.directory, metrics: metrics, logger: AppState.log))
    }

    var body: some View {
        let size = instance.size
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1)
        let theme = instance.theme(isDark: colorScheme == .dark)
        Group {
            if case .failed = controller.state {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if let tree = controller.tree {
                WidgetTreeView(node: tree, theme: theme, sizeClass: instance.sizeClass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .environment(\.colorScheme, instance.resolvedIsDark(colorScheme == .dark) ? .dark : .light)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: instance.cornerRadius, style: .continuous))
        .widgetBackground(instance.background, cornerRadius: instance.cornerRadius)
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .task(id: activity.isOpen) {
            guard activity.isOpen else { controller.stop(); return }
            await controller.start(size: size, sizeClass: instance.sizeClass, theme: theme, settings: instance.settings)
        }
        .onChange(of: instance) {
            guard activity.isOpen else { return }
            controller.update(size: instance.size, sizeClass: instance.sizeClass,
                              theme: instance.theme(isDark: colorScheme == .dark), settings: instance.settings)
        }
        .onDisappear { controller.stop() }
    }
}
