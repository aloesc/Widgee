import AppKit
import SwiftUI

/// Окна «Галерея» и панели настроек экземпляров.
@MainActor
final class AuxWindows {
    private unowned let state: AppState
    private var gallery: NSWindow?
    let activity = GalleryActivity()
    private var closeObserver: NSObjectProtocol?
    private var settings: [UUID: NSWindow] = [:]

    /// Окна, пока открытых хотя бы одно из которых приложение живёт в Dock; иначе только в строке меню.
    private var tracked: [NSWindow] = []
    private var policyObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        policyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closing = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let closing, self.tracked.contains(where: { ObjectIdentifier($0) == closing }) else { return }
                // willClose приходит до скрытия окна, поэтому проверяем на следующем цикле.
                DispatchQueue.main.async { self.updateActivationPolicy() }
            }
        }
    }

    private func updateActivationPolicy() {
        let hasOpenWindow = tracked.contains { $0.isVisible || $0.isMiniaturized }
        NSApp.setActivationPolicy(hasOpenWindow ? .regular : .accessory)
    }

    func showMain() {
        if gallery == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Widgee"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden  // тема окна следует системе
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 960, height: 640)
            let host = NSHostingController(rootView: MainWindowView(state: state, catalog: state.catalog).environmentObject(activity))
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 1180, height: 780))
            w.center()
            gallery = w
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.activity.isOpen = false }
            }
        }
        activity.isOpen = true
        present(gallery!)
    }

    func showSettings(_ id: UUID) {
        if settings[id] == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 720),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Widget Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: InstanceSettingsView(state: state, id: id))
            w.center()
            settings[id] = w
        }
        present(settings[id]!)
    }

    func closeSettings(_ id: UUID) {
        settings[id]?.close()
        settings[id] = nil
    }

    private func present(_ w: NSWindow) {
        if !tracked.contains(where: { $0 === w }) { tracked.append(w) }
        NSApp.setActivationPolicy(.regular)  // значок в Dock и меню приложения, пока открыто окно
        w.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}
