import ServiceManagement
import SwiftUI
import WidgeeCore

@main
struct WidgeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // macOS запоминает скрытие значка в строке меню (⌘-перетаскивание, «Allow in the Menu Bar»).
        // У приложения без дока значок — главный вход, поэтому при запуске снимаем сохранённое скрытие.
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
    }

    var body: some Scene {
        MenuBarExtra("Widgee", systemImage: "square.grid.2x2") {
            MenuContent(state: delegate.state)
        }
        .menuBarExtraStyle(.window)
        .commands { WidgeeCommands(state: delegate.state) }
    }
}

/// Меню приложения в верхней строке (Widgee / Widgets / Help).
struct WidgeeCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Widgee") { state.openAbout() }  // раздел Settings
        }
        CommandGroup(replacing: .newItem) {
            Button("Create Widget…") { state.openCreate() }
                .keyboardShortcut("n")
        }
        CommandMenu("Widgets") {
            Button("Gallery") { state.openGallery() }
                .keyboardShortcut("g")
            Toggle("Edit Mode", isOn: $state.isEditing)
                .keyboardShortcut("e")
            Button("Layout…") { state.openLayout() }
            Button("Open Widgets Folder") { state.openWidgetsFolder() }
        }
        CommandGroup(replacing: .help) {
            Button("Support the Developer ❤️") { AppLinks.open(AppLinks.donate) }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Закрывает поповер строки меню после действия (в обычном окне предпросмотра ничего не делает).
    private func run(_ action: () -> Void) {
        if let w = NSApp.keyWindow, w is NSPanel { w.orderOut(nil) }
        action()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 12) {
            header
            Button { run { state.openGallery() } } label: {
                Label("Open Widgee", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(MenuButtonStyle(kind: .prominent))
            .accessibilityLabel("Open Widgee")
            .accessibilityHint("Opens the main window")
            HStack(spacing: 8) {
                tile("Gallery", "square.grid.2x2", hint: "Opens the widget gallery") { state.openGallery() }
                tile("Create", "plus.square.dashed", hint: "Opens the widget creation guide") { state.openCreate() }
                tile("Layout", "rectangle.3.group", hint: "Opens layout and snapping settings") { state.openLayout() }
            }
            editCard
            HStack {
                Button { run { AppLinks.open(AppLinks.donate) } } label: {
                    Text("Support the Developer ❤️").font(.callout).padding(.horizontal, 8).frame(minHeight: 28)
                }
                .buttonStyle(MenuButtonStyle(kind: .quiet))
                .accessibilityLabel("Support the Developer")
                .accessibilityHint("Opens the donation page")
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    HStack(spacing: 6) {
                        Text("Quit").font(.callout)
                        Text("⌘Q").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).frame(minHeight: 28)
                }
                .buttonStyle(MenuButtonStyle(kind: .quiet))
                .keyboardShortcut("q")
                .accessibilityLabel("Quit Widgee")
            }
        }
        .padding(14)
        .frame(width: 300)
        .modifier(MenuBackground(reduce: reduceTransparency, shape: shape))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Widgee").font(.headline)
                    Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                }
                let n = state.instances.count
                Text("\(n) \(n == 1 ? "widget" : "widgets") on desktop").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ title: String, _ symbol: String, hint: String, action: @escaping () -> Void) -> some View {
        Button { run(action) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(height: 24)
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(MenuButtonStyle(kind: .tile))
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private var editCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.dashed.inset.filled")
                .font(.system(size: 18)).foregroundStyle(.tint).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Edit Mode").font(.callout.weight(.semibold))
                Text("Move and resize widgets").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Edit Mode", isOn: $state.isEditing)
                .labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("Edit Mode")
                .accessibilityHint("Turns on moving and resizing of widgets on the desktop")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

private struct MenuBackground: ViewModifier {
    let reduce: Bool
    let shape: RoundedRectangle
    func body(content: Content) -> some View {
        if reduce {
            content.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

private struct MenuButtonStyle: ButtonStyle {
    enum Kind { case prominent, tile, quiet }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, kind: kind)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @State private var hover = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: kind == .quiet ? 10 : 14, style: .continuous)
            let p = configuration.isPressed
            configuration.label
                .foregroundStyle(kind == .prominent ? Color.white : Color.primary)
                .background(shape.fill(fill(p)))
                .overlay { if focused { shape.strokeBorder(Color.accentColor, lineWidth: 2.5) } }
                .contentShape(shape)
                .scaleEffect(p ? 0.97 : (hover && kind == .tile ? 1.04 : 1))
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.35), value: hover)
                .onHover { hover = $0 }
        }

        private func fill(_ pressed: Bool) -> Color {
            switch kind {
            case .prominent: Color(red: 0.0, green: 0.42, blue: 0.9).opacity(pressed ? 0.75 : (hover ? 1 : 0.92))
            case .tile: Color.primary.opacity(pressed ? 0.22 : (hover ? 0.16 : 0.08))
            case .quiet: Color.primary.opacity(pressed ? 0.2 : (hover ? 0.12 : 0))
            }
        }
    }
}

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            AppState.logger.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.bootstrap()
        state.desktop.startObservingAppearance()
        #if DEBUG
        DebugCommands.run(state)
        #endif
    }

    /// Обычное приложение: значок в Dock, закрытие галереи не завершает работу (виджеты остаются на столе).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Gallery", action: #selector(dockGallery), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Create Widget…", action: #selector(dockCreate), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Support the Developer ❤️", action: #selector(dockSupport), keyEquivalent: "").target = self
        return menu
    }

    @objc private func dockGallery() { state.openGallery() }
    @objc private func dockCreate() { state.openCreate() }
    @objc private func dockSupport() { AppLinks.open(AppLinks.donate) }

    /// Повторный запуск из Finder/Spotlight открывает галерею: клик по значку в Dock или повторный запуск открывает галерею.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state.openGallery()
        return true
    }
}
