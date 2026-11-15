import AppKit
import SwiftUI

/// Плавающая стеклянная капсула «Editing widgets» по центру сверху главного экрана на время режима редактирования.
/// Позволяет выйти из режима без главного окна и без значка в строке меню.
@MainActor
final class EditPanelController {
    private unowned let state: AppState
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func setVisible(_ on: Bool) {
        if !on { panel?.orderOut(nil); return }
        if panel == nil { panel = makePanel() }
        reposition()
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: EditPanelView(
            layout: { [weak state] in state?.openLayout() },
            done: { [weak state] in state?.isEditing = false }))
        host.sizingOptions = []
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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
        return p
    }

    /// По центру видимой области главного экрана, под строкой меню.
    private func reposition() {
        guard let p = panel, let s = NSScreen.screens.first else { return }
        let vf = s.visibleFrame, size = p.frame.size
        p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 10))
    }
}

private struct EditPanelView: View {
    let layout: () -> Void
    let done: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
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
        }
        .controlSize(.regular)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background {
            if reduceTransparency { Capsule().fill(Color(nsColor: .windowBackgroundColor)) }
            else { Color.clear.glassEffect(.regular, in: Capsule()) }
        }
        .padding(6)
        .fixedSize()
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
