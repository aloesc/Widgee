import AppKit
import Background
import Renderer
import SwiftUI
import WidgeeCore
import WidgetHost

struct InstanceActions {
    var resize: (WidgetSizePreset) -> Void
    var remove: () -> Void
    var openSettings: () -> Void
    var dragMove: (NSPoint, Bool) -> Void
    var dragEnd: (Bool) -> Void
    var resizeMove: (CGSize, Bool) -> Void
    var resizeEnd: () -> Void
    var restart: () -> Void
}

/// Содержимое окна виджета: дерево из JS, фон, плашка сбоя и оверлей режима редактирования.
struct WidgetInstanceView: View {
    @ObservedObject var model: InstanceModel
    @ObservedObject var controller: WidgetController
    let allowedSizes: Set<String>
    let actions: InstanceActions
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let inst = model.instance
        let shape = RoundedRectangle(cornerRadius: inst.cornerRadius, style: .continuous)
        ZStack {
            content(inst)
            if model.isEditing { EditOverlay(model: model, allowedSizes: allowedSizes, actions: actions) }
        }
        // Жёсткий размер: иначе минимальный размер содержимого растягивает окно.
        .frame(width: inst.width, height: inst.height)
        .clipped()
        .clipShape(shape)
        .widgetBackground(inst.background, cornerRadius: inst.cornerRadius)
    }

    @ViewBuilder private func content(_ inst: WidgetInstance) -> some View {
        if case .failed(let message) = controller.state {
            FailedPlate(message: message, restart: actions.restart)
        } else if let tree = controller.tree {
            WidgetTreeView(node: tree, theme: inst.theme(isDark: colorScheme == .dark), sizeClass: inst.sizeClass)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.colorScheme, inst.resolvedIsDark(colorScheme == .dark) ? .dark : .light)
        } else {
            Color.clear
        }
    }
}

struct FailedPlate: View {
    let message: String
    let restart: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.orange)
            Text("Widget crashed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.center)
            Button("Restart", action: restart).buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(12)
    }
}

// MARK: - Режим редактирования

private enum ChipPlacement {
    case belowLeading, belowTrailing, aboveCenter, aboveTrailing
    var alignment: Alignment {
        switch self {
        case .belowLeading: .bottomLeading
        case .belowTrailing: .bottomTrailing
        case .aboveCenter: .top
        case .aboveTrailing: .topTrailing
        }
    }
    var dy: CGFloat {
        switch self {
        case .belowLeading, .belowTrailing: 30
        case .aboveCenter, .aboveTrailing: -30
        }
    }
}

private struct ChipLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Стиль кнопок оверлея: увеличение при наведении, нажатие, мгновенная подпись-чип, кольцо фокуса.
private struct EditButtonStyle: ButtonStyle {
    let chip: String
    let placement: ChipPlacement
    var capsule = false
    var glass = true

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, style: self)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let style: EditButtonStyle
        @State private var hover = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.isFocused) private var focused

        var body: some View {
            let shape: AnyShape = style.capsule ? AnyShape(Capsule()) : AnyShape(Circle())
            configuration.label
                .background {
                    if style.glass {
                        if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
                        else { Color.clear.glassEffect(.regular.interactive(), in: shape) }
                    }
                }
                .background(shape.fill(Color.white.opacity(hover ? 0.28 : 0)))
                .overlay { if hover { shape.stroke(Color.white.opacity(0.7), lineWidth: 1.5) } }
                .overlay { if focused { shape.stroke(Color.accentColor, lineWidth: 2.5).padding(-2) } }
                .scaleEffect(configuration.isPressed ? 0.94 : (hover ? 1.1 : 1))
                .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.45), value: hover)
                .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.2), value: configuration.isPressed)
                .onHover { hover = $0 }
                .overlay(alignment: style.placement.alignment) {
                    if hover { ChipLabel(text: style.chip).offset(y: style.placement.dy).transition(.opacity) }
                }
                .zIndex(hover ? 10 : 0)
        }
    }
}

private struct EditOverlay: View {
    @ObservedObject var model: InstanceModel
    let allowedSizes: Set<String>
    let actions: InstanceActions
    @State private var moveHint = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static var hintShownThisSession = false

    var body: some View {
        let inst = model.instance
        let current = WidgetSizePreset(sizeClass: inst.sizeClass)
        let compact = inst.width < 230
        ZStack {
            DragHandle(actions: actions, onEnter: showMoveHint)
            RoundedRectangle(cornerRadius: inst.cornerRadius, style: .continuous)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .allowsHitTesting(false)
            VStack {
                HStack {
                    circleButton("xmark", label: "Remove widget", hint: "Removes this widget from the desktop",
                                 chip: "Remove widget", placement: .belowLeading, action: actions.remove)
                    Spacer()
                    circleButton("slider.horizontal.3", label: "Widget settings", hint: "Opens settings for this widget",
                                 chip: "Widget settings", placement: .belowTrailing, action: actions.openSettings)
                }
                if compact { Spacer(); sizeBar(inst, current); Spacer() } else { Spacer(); sizeBar(inst, current) }
            }
            .padding(max(8, inst.cornerRadius * 0.35))
            ResizeGrip(size: inst.size, inset: max(10, inst.cornerRadius * 0.4), actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if let text = model.hud ?? (moveHint ? "Drag to move" : nil) {
                ChipLabel(text: text)
                    .font(.system(size: 13, weight: .semibold))
                    .scaleEffect(model.hud != nil ? 1.15 : 1)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
    }

    private func showMoveHint() {
        guard !Self.hintShownThisSession else { return }
        Self.hintShownThisSession = true
        moveHint = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            moveHint = false
        }
    }

    private func sizeBar(_ inst: WidgetInstance, _ current: WidgetSizePreset?) -> some View {
        HStack(spacing: 2) {
            ForEach(WidgetSizePreset.allCases, id: \.self) { p in
                let on = current == p
                let allowed = allowedSizes.contains(p.rawValue)
                Button { actions.resize(p) } label: {
                    Text(p.cellLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .contentShape(Capsule())
                }
                .buttonStyle(EditButtonStyle(chip: "Size: \(p.cellLabel) cells", placement: .aboveCenter, capsule: true, glass: false))
                .focusable(interactions: .activate)
                .disabled(!allowed)
                .opacity(allowed ? 1 : 0.35)
                .help("Size: \(p.cellLabel) cells")
                .accessibilityLabel("Size \(p.cellLabel)")
                .accessibilityHint(allowed ? "Resizes the widget to \(p.cellLabel) cells" : "Not available for this widget")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background {
            if reduceTransparency { Capsule().fill(Color(nsColor: .windowBackgroundColor)) }
            else { Color.clear.glassEffect(.regular, in: Capsule()) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Widget size")
        .accessibilityValue(current.map { "\($0.cellLabel) cells" } ?? "Custom")
    }

    private func circleButton(_ symbol: String, label: String, hint: String, chip: String,
                              placement: ChipPlacement, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(EditButtonStyle(chip: chip, placement: placement))
        .focusable(interactions: .activate)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

/// Перетаскивание окна за фон в режиме редактирования (по экранным координатам мыши).
/// Позицию корректирует контроллер окон (прилипание, направляющие); ⌥ временно отключает прилипание.
private struct DragHandle: NSViewRepresentable {
    let actions: InstanceActions
    let onEnter: () -> Void
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) { v.actions = actions; v.onEnter = onEnter }

    final class DragView: NSView {
        var actions: InstanceActions?
        var onEnter: (() -> Void)?
        private var startMouse = NSPoint.zero
        private var startOrigin = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            // Область с .inVisibleRect сама следует за видом; пересоздаём только если её ещё нет,
            // иначе каждое обновление геометрии рождает ложные enter/exit.
            guard trackingAreas.isEmpty else { return }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onEnter?() }
        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startOrigin = window?.frame.origin ?? .zero
            NSCursor.closedHand.set()
        }
        override func mouseDragged(with event: NSEvent) {
            let m = NSEvent.mouseLocation
            NSCursor.closedHand.set()
            actions?.dragMove(NSPoint(x: startOrigin.x + m.x - startMouse.x, y: startOrigin.y + m.y - startMouse.y),
                              event.modifierFlags.contains(.option))
        }
        override func mouseUp(with event: NSEvent) {
            actions?.dragEnd(event.modifierFlags.contains(.option))
            NSCursor.openHand.set()
        }
    }
}

/// Ручка свободного изменения размера в правом нижнем углу (левый верхний угол остаётся на месте).
private struct ResizeGrip: View {
    let size: CGSize
    let inset: CGFloat
    let actions: InstanceActions
    @State private var hover = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isFocused) private var focused

    var body: some View {
        // Область наведения неподвижна (30×30, без масштабирования и оверлеев), а вся анимация рисуется
        // отдельным слоем, который не принимает мышь: иначе изменение вида при наведении двигает область
        // наведения, наведение пропадает, и ручка начинает мигать.
        ZStack {
            visual.allowsHitTesting(false)
            GripView(actions: actions, hover: $hover, pressed: $pressed)
        }
        .frame(width: 30, height: 30)
        .overlay(alignment: .topTrailing) {
            if hover && !pressed {
                ChipLabel(text: "Resize — drag to change size")
                    .offset(y: -30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
        .padding(inset)
        .help("Resize — drag to change size")
        .focusable(interactions: .activate)
        .onKeyPress(phases: [.down, .repeat]) { press in
            let step: CGFloat = 20
            var d = CGSize.zero
            switch press.key {
            case .rightArrow: d.width = step
            case .leftArrow: d.width = -step
            case .downArrow: d.height = step
            case .upArrow: d.height = -step
            default: return .ignored
            }
            actions.resizeMove(CGSize(width: size.width + d.width, height: size.height + d.height), false)
            actions.resizeEnd()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize widget")
        .accessibilityHint("Drag to change the size. With VoiceOver, swipe up or down to adjust.")
        .accessibilityValue("\(Int(size.width)) by \(Int(size.height)) points")
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { dir in
            let step: CGFloat = dir == .increment ? 20 : -20
            actions.resizeMove(CGSize(width: size.width + step, height: size.height + step), false)
            actions.resizeEnd()
        }
    }

    private var visual: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 13, weight: .bold))
            .rotationEffect(.degrees(90))
            .frame(width: 30, height: 30)
            .background {
                if reduceTransparency { Circle().fill(Color(nsColor: .windowBackgroundColor)) }
                else { Color.clear.glassEffect(.regular, in: Circle()) }  // не .interactive(): у него своя реакция на мышь
            }
            .background(Circle().fill(Color.white.opacity(hover || pressed ? 0.28 : 0)))
            .overlay { if hover || pressed { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5) } }
            .overlay { if focused { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-2) } }
            .scaleEffect(pressed ? 0.94 : (hover ? 1.08 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hover)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
    }

    struct GripView: NSViewRepresentable {
        let actions: InstanceActions
        @Binding var hover: Bool
        @Binding var pressed: Bool
        func makeNSView(context: Context) -> GripNSView { GripNSView() }
        func updateNSView(_ v: GripNSView, context: Context) {
            v.actions = actions
            v.onHover = { h in DispatchQueue.main.async { hover = h } }
            v.onPress = { p in DispatchQueue.main.async { pressed = p } }
        }
    }

    final class GripNSView: NSView {
        var actions: InstanceActions?
        var onHover: ((Bool) -> Void)?
        var onPress: ((Bool) -> Void)?
        private var startMouse = NSPoint.zero
        private var startSize = CGSize.zero
        private static var cursor: NSCursor { .frameResize(position: .bottomRight, directions: .all) }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: Self.cursor) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startSize = window?.frame.size ?? .zero
            Self.cursor.set()
            onPress?(true)
        }
        override func mouseDragged(with event: NSEvent) {
            let m = NSEvent.mouseLocation
            Self.cursor.set()
            actions?.resizeMove(CGSize(width: startSize.width + m.x - startMouse.x,
                                       height: startSize.height - (m.y - startMouse.y)),
                                event.modifierFlags.contains(.option))
        }
        override func mouseUp(with event: NSEvent) {
            actions?.resizeEnd()
            onPress?(false)
        }
    }
}
