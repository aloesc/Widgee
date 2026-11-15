#if DEBUG
import AppKit
import Layout
import WidgeeCore
import SwiftUI

/// Автотест без кликов по menu bar (только Debug):
/// --open-section gallery|mine|create|layout|settings (алиасы --open-gallery/-create/-layout/-about), --add-widget <id> [--preset S|M|L|XL] [--set key=value]..., --edit,
/// --bg glass|clear|color|tint, --resize S|M|L|XL, --open-settings
func dlog(_ s: String) {
    FileHandle.standardError.write(Data(("[debug] " + s + "\n").utf8))
}

@MainActor private var backdropWindow: NSWindow?
@MainActor private var menuPreviewWindow: NSWindow?

@MainActor
enum DebugCommands {
    static func run(_ state: AppState) {
        let a = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
            return a[i + 1]
        }
        // --add-widget id[:preset[:x:y[:k=v,k=v]]] (можно несколько раз)
        for (i, x) in a.enumerated() where x == "--add-widget" && i + 1 < a.count {
            let p = a[i + 1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let entry = state.catalog.entry(p[0]) else { continue }
            var settings: [String: JSONValue] = [:]
            if p.count > 4 {
                for pair in p[4].split(separator: ",") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    guard kv.count == 2 else { continue }
                    if kv[1] == "true" { settings[kv[0]] = .bool(true) }
                    else if kv[1] == "false" { settings[kv[0]] = .bool(false) }
                    else { settings[kv[0]] = .string(kv[1]) }
                }
            }
            let preset = (p.count > 1 ? WidgetSizePreset(rawValue: p[1]) : nil) ?? entry.defaultPreset
            state.addWidget(entry, preset: preset, settings: settings)
            if p.count > 3, let px = Double(p[2]), let py = Double(p[3]), let last = state.instances.last {
                state.update(last.id) { $0.offsetX = px; $0.offsetY = py }
            }
        }
        // --backdrop: цветная подложка под виджетами (только для проверки фона/стекла скриншотами).
        if a.contains("--backdrop"), let sf = NSScreen.screens.first?.frame {
            let w = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: LinearGradient(
                colors: [.orange, .yellow, .green, .teal, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            w.orderFrontRegardless()
            backdropWindow = w
        }
        if let bg = value("--bg"), bg != "keep" {
            for inst in state.instances {
                state.update(inst.id) {
                    switch bg {
                    case "clear": $0.background = .clear
                    case "color": $0.background = .color(hex: "#FF9F0A", opacity: 0.85)
                    case "tint": $0.background = .tint(hex: "#FF375F", opacity: 0.6)
                    default: $0.background = .liquidGlass
                    }
                }
            }
        }
        if let r = value("--resize").flatMap(WidgetSizePreset.init(rawValue:)) {
            for inst in state.instances { state.resize(inst.id, to: r) }
        }
        // --layout grid=6x4|grid=off,snap=off,center=off,edges=off,widgets=off,margin=N,dist=N,gap=N,gmargin=N
        if let spec = value("--layout") {
            var l = state.layout
            for tok in spec.split(separator: ",") {
                let kv = tok.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                let on = kv[1] != "off"
                switch kv[0] {
                case "grid":
                    if kv[1] == "off" { l.grid.enabled = false }
                    else {
                        let cr = kv[1].split(separator: "x").compactMap { Int($0) }
                        if cr.count == 2 { l.grid.enabled = true; l.grid.columns = cr[0]; l.grid.rows = cr[1] }
                    }
                case "snap": l.snapEnabled = on
                case "center": l.snapToScreenCenter = on
                case "edges": l.snapToScreenEdges = on
                case "widgets": l.snapToWidgets = on
                case "margin": l.edgeMargin = CGFloat(Double(kv[1]) ?? 20)
                case "dist": l.snapThreshold = CGFloat(Double(kv[1]) ?? 10)
                case "gap": l.grid.gap = CGFloat(Double(kv[1]) ?? 12)
                case "gmargin": l.grid.margin = CGFloat(Double(kv[1]) ?? 24)
                case "showgrid": l.showGridInEditMode = on
                default: break
                }
            }
            state.layout = l
            dlog("layout: \(l)")
        }
        if a.contains("--edit") { state.isEditing = true }
        // --edit-off-after N: через N с выключает режим редактирования и логирует видимость панели.
        if let n = value("--edit-off-after").flatMap(Double.init) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(n))
                dlog("edit panel shown (editing=\(state.isEditing)): \(state.editPanel.isShown)")
                state.isEditing = false
                dlog("edit panel shown (editing=\(state.isEditing)): \(state.editPanel.isShown)")
            }
        }
        // --simulate-drag idx:dx:dy[:opt][:hold]  /  --simulate-resize idx:w:h[:opt][:hold]  /  --simulate-preset idx:S|M|L|XL
        // Тот же код, что при реальной мыши; hold = не «отпускать» (направляющие остаются на оверлее).
        // --simulate-drag-to idx:x:y  — абсолютный origin окна.
        for (i, x) in a.enumerated() where i + 1 < a.count && ["--simulate-drag", "--simulate-drag-to", "--simulate-resize", "--simulate-preset"].contains(x) {
            let p = a[i + 1].split(separator: ":").map(String.init)
            guard p.count >= 3 || (x == "--simulate-preset" && p.count == 2), let idx = Int(p[0]), idx < state.instances.count else { continue }
            let id = state.instances[idx].id
            guard let f0 = state.desktop.currentFrame(of: id) else { continue }
            let opt = p.contains("opt"), hold = p.contains("hold")
            switch x {
            case "--simulate-drag", "--simulate-drag-to":
                let dx = Double(p[1]) ?? 0, dy = Double(p[2]) ?? 0
                let o = x == "--simulate-drag" ? NSPoint(x: f0.minX + dx, y: f0.minY + dy) : NSPoint(x: dx, y: dy)
                state.desktop.dragMove(id, to: o, optionHeld: opt)
                dlog("drag[\(idx)] before=\(f0) proposed=\(o) after-snap=\(state.desktop.currentFrame(of: id)!) guides=\(state.desktop.overlay.guides.map { "\($0.axis)@\($0.position)/\($0.kind)" })")
                if !hold { state.desktop.dragEnd(id, optionHeld: opt); dlog("drop[\(idx)] frame=\(state.desktop.currentFrame(of: id)!)") }
            case "--simulate-resize":
                state.desktop.resizeMove(id, size: CGSize(width: Double(p[1]) ?? 0, height: Double(p[2]) ?? 0), optionHeld: opt)
                dlog("resize[\(idx)] before=\(f0) after=\(state.desktop.currentFrame(of: id)!) guides=\(state.desktop.overlay.guides.map { "\($0.axis)@\($0.position)/\($0.kind)" })")
                if !hold { state.desktop.resizeEnd(id); dlog("resize-end[\(idx)] frame=\(state.desktop.currentFrame(of: id)!) class=\(state.instances[idx].sizeClass)") }
            default:
                if let pr = WidgetSizePreset(rawValue: p[1]) {
                    state.resize(id, to: pr)
                    dlog("preset[\(idx)] \(pr) before=\(f0) after=\(state.desktop.currentFrame(of: id)!)")
                }
            }
        }
        // --screenshot-overlay path: композитный PNG основного экрана (рамки виджетов + оверлей сетки/направляющих).
        if let path = value("--screenshot-overlay"), let s = NSScreen.screens.first {
            dlog("screen frame=\(s.frame) visible=\(s.visibleFrame)")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                guard let m = state.desktop.overlay.model(for: s) else { dlog("no overlay window (nothing to draw)"); return }
                let f = s.frame
                let widgets = state.desktop.debugWidgetFrames
                let view = ZStack(alignment: .topLeading) {
                    Color(white: 0.93)
                    ForEach(Array(widgets.enumerated()), id: \.offset) { _, r in
                        RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue, lineWidth: 1))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX - f.minX, y: f.maxY - r.maxY)
                    }
                    OverlayView(model: m)
                }.frame(width: f.width, height: f.height)
                let r = ImageRenderer(content: view)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path)); dlog("screenshot written \(path)")
                }
            }
        }
        if a.contains("--dump-frames") { dlog("frames=\(state.desktop.debugWidgetFrames)") }
        // --appearance light|dark: принудительная тема приложения (для скриншотов).
        if let ap = value("--appearance") {
            NSApp.appearance = NSAppearance(named: ap == "dark" ? .darkAqua : .aqua)
        }
        // --gallery-category all|today|weather|battery|clock|other; --select-widget <id|index>[:S|M|L|XL]
        if let c = value("--gallery-category"), let cat = GalleryCategory.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(c.lowercased()) }) {
            state.galleryCategory = cat
        }
        if let sel = value("--select-widget") {
            let parts = sel.split(separator: ":").map(String.init)
            state.galleryRequest = GalleryRequest(key: parts[0], preset: parts.count > 1 ? WidgetSizePreset(rawValue: parts[1]) : nil)
        }
        // --open-section gallery|create|layout|settings; старые флаги — алиасы.
        var sec = value("--open-section").flatMap(MainSection.init(rawValue:))
        if a.contains("--open-layout") { sec = .layout }
        if a.contains("--open-about") { sec = .settings }
        if a.contains("--open-create") { sec = .create }
        if a.contains("--open-gallery") { sec = .gallery }
        if let sec {
            state.openSection(sec)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                dlog("main window: \(NSApp.windows.filter { $0.title == "Widgee" }.map(\.windowNumber)) section=\(sec.rawValue) policy=\(NSApp.activationPolicy().rawValue)")
            }
        }
        // --close-main: через 3 с закрывает главное окно и логирует политику активации (проверка Dock).
        if a.contains("--close-main") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                NSApp.windows.first { $0.title == "Widgee" }?.close()
                try? await Task.sleep(for: .seconds(1))
                dlog("after close: policy=\(NSApp.activationPolicy().rawValue)")
            }
        }
        // --open-menu-preview: содержимое поповера строки меню в обычном окне (для скриншота).
        if a.contains("--open-menu-preview") {
            let w = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 330, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "MenuPreview"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MenuContent(state: state).padding(15)
                .background(LinearGradient(colors: [.orange, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)))
            w.makeKeyAndOrderFront(nil)
            menuPreviewWindow = w
        }
        if a.contains("--donate") { AppLinks.open(AppLinks.donate) }
        if a.contains("--open-settings"), let f = state.instances.first { state.openSettings(f.id) }
    }
}
#endif
