import Background
import Renderer
import SwiftUI
import WidgeeCore
import WidgetHost

/// Панель настроек экземпляра: фон, радиус, шрифт, акцент и `settings` из манифеста.
struct InstanceSettingsView: View {
    @ObservedObject var state: AppState
    let id: UUID

    private enum BGKind: String, CaseIterable, Identifiable {
        case glass = "Liquid Glass", clear = "Clear", color = "Color", tint = "Tint"
        var id: String { rawValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastHex = "#0A84FF"
    @State private var lastOpacity = 0.6

    var body: some View {
        if let inst = state.instance(id) {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    CardSection(title: "Background", symbol: "drop.fill", tint: .blue) {
                        Picker("Type", selection: kindBinding(inst)) {
                            ForEach(BGKind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Background type")
                        if kind(of: inst.background) == .color || kind(of: inst.background) == .tint {
                            ColorPicker("Color", selection: colorBinding(inst), supportsOpacity: false)
                            SliderRow("Opacity", value: opacityBinding(inst), in: 0...1, format: { "\(Int($0 * 100)) %" })
                        }
                    }
                    CardSection(title: "Appearance", symbol: "paintbrush.fill", tint: .pink) {
                        SliderRow("Corner radius", value: binding(inst, \.cornerRadius), in: 0...60, format: { "\(Int($0))" })
                        SettingRow(label: "Font") {
                            FontPickerButton(choice: Binding(
                                get: { FontChoice(design: inst.fontDesign, family: inst.fontFamily) },
                                set: { c in state.update(id) { $0.fontDesign = c.design; $0.fontFamily = c.family } }))
                        }
                        FontWeightRow(choice: FontChoice(design: inst.fontDesign, family: inst.fontFamily),
                                      weight: Binding(get: { inst.fontWeight }, set: { v in state.update(id) { $0.fontWeight = v } }))
                        SettingRow(label: "Text appearance") {
                            Picker("Text appearance", selection: Binding(
                                get: { inst.textAppearance ?? .auto }, set: { v in state.update(id) { $0.textAppearance = v == .auto ? nil : v } })) {
                                Text("Auto").tag(TextAppearance.auto)
                                Text("Light (dark text)").tag(TextAppearance.light)
                                Text("Dark (light text)").tag(TextAppearance.dark)
                            }.labelsHidden().fixedSize()
                        }
                        TextSizeRow(scale: Binding(
                            get: { inst.textScale }, set: { v in state.update(id) { $0.textScale = v } }))
                        ColorPicker("Accent color", selection: accentBinding(inst), supportsOpacity: false)
                    }
                    CardSection(title: "Alignment", symbol: "text.alignleft", tint: .teal) {
                        Picker("Alignment", selection: Binding(
                            get: { inst.alignment ?? .auto }, set: { v in state.update(id) { $0.alignment = v == .auto ? nil : v } })) {
                            Text("Auto").tag(ContentAlignment.auto)
                            Text("Left").tag(ContentAlignment.left)
                            Text("Center").tag(ContentAlignment.center)
                            Text("Right").tag(ContentAlignment.right)
                        }
                        .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Alignment")
                    }
                    if let entry = state.catalog.entry(inst.widgetID), !entry.manifest.settings.isEmpty {
                        CardSection(title: "Widget settings", symbol: "slider.horizontal.3", tint: .orange) {
                            ForEach(entry.manifest.settings.filter { isVisible($0, entry: entry, inst: inst) }, id: \.key) { field in
                                fieldView(field, entry: entry, inst: inst)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Space.xs).padding(.bottom, DS.Space.xs)
            }
            .scrollClipDisabled()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: inst.settings)
            .onAppear {
                lastHex = hex(of: inst.background) ?? lastHex
                lastOpacity = hex(of: inst.background) == nil ? lastOpacity : opacity(of: inst.background)
            }
        } else {
            Text("Widget removed").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: фон

    private func kind(of s: WidgetBackgroundStyle) -> BGKind {
        switch s { case .liquidGlass: .glass; case .clear: .clear; case .color: .color; case .tint: .tint }
    }
    private func hex(of s: WidgetBackgroundStyle) -> String? {
        switch s { case .color(let h, _), .tint(let h, _): h; default: nil }
    }
    private func opacity(of s: WidgetBackgroundStyle) -> Double {
        switch s { case .color(_, let o), .tint(_, let o): o; default: lastOpacity }
    }
    private func make(_ k: BGKind, hex: String, opacity: Double) -> WidgetBackgroundStyle {
        switch k {
        case .glass: .liquidGlass
        case .clear: .clear
        case .color: .color(hex: hex, opacity: opacity)
        case .tint: .tint(hex: hex, opacity: opacity)
        }
    }
    private func kindBinding(_ inst: WidgetInstance) -> Binding<BGKind> {
        Binding(get: { kind(of: inst.background) }, set: { k in
            let h = hex(of: inst.background) ?? lastHex, o = opacity(of: inst.background)
            lastHex = h; lastOpacity = o
            state.update(id) { $0.background = make(k, hex: h, opacity: o) }
        })
    }
    private func colorBinding(_ inst: WidgetInstance) -> Binding<Color> {
        Binding(get: { Color(hex: hex(of: inst.background) ?? lastHex) ?? .blue }, set: { c in
            let k = kind(of: inst.background), o = opacity(of: inst.background)
            lastHex = c.hexString
            state.update(id) { $0.background = make(k, hex: c.hexString, opacity: o) }
        })
    }
    private func opacityBinding(_ inst: WidgetInstance) -> Binding<Double> {
        Binding(get: { opacity(of: inst.background) }, set: { o in
            let k = kind(of: inst.background), h = hex(of: inst.background) ?? lastHex
            lastOpacity = o
            state.update(id) { $0.background = make(k, hex: h, opacity: o) }
        })
    }

    private func binding<V>(_ inst: WidgetInstance, _ kp: WritableKeyPath<WidgetInstance, V>) -> Binding<V> {
        Binding(get: { inst[keyPath: kp] }, set: { v in state.update(id) { $0[keyPath: kp] = v } })
    }
    private func accentBinding(_ inst: WidgetInstance) -> Binding<Color> {
        Binding(get: { Color(hex: inst.accentHex) ?? .blue }, set: { c in state.update(id) { $0.accentHex = c.hexString } })
    }

    // MARK: settings манифеста

    private func isVisible(_ f: WidgetSettingFieldInfo, entry: CatalogEntry, inst: WidgetInstance) -> Bool {
        f.showIf?.isSatisfied(values: inst.settings, fields: entry.manifest.settings) ?? true
    }

    private func setting(_ key: String, _ v: JSONValue) { state.update(id) { $0.settings[key] = v } }

    @ViewBuilder private func fieldView(_ f: WidgetSettingFieldInfo, entry: CatalogEntry, inst: WidgetInstance) -> some View {
        let current = inst.settings[f.key] ?? f.default
        switch f.type {
        case "boolean":
            Toggle(f.label, isOn: Binding(get: { current?.boolValue ?? false }, set: { setting(f.key, .bool($0)) }))
        case "number":
            labeled(f.label) {
                TextField(f.label, value: Binding(get: { current?.numberValue ?? 0 }, set: { setting(f.key, .number($0)) }),
                          format: .number).textFieldStyle(.roundedBorder)
            }
        case "color":
            ColorPicker(f.label, selection: Binding(get: { Color(hex: current?.stringValue ?? "") ?? .blue },
                                                    set: { setting(f.key, .string($0.hexString)) }),
                        supportsOpacity: false)
                .accessibilityLabel(f.label)
        case "city":
            CityPickerView(label: f.label, current: CitySetting(json: current)) { setting(f.key, $0.json) }
        case "select":
            if let options = entry.selectOptions[f.key], !options.isEmpty {
                Picker(f.label, selection: Binding(get: { current?.stringValue ?? options[0] },
                                                    set: { setting(f.key, .string($0)) })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    stringField(f, current)
                    Text("The manifest defines no options for this field; enter the value manually.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        default:
            stringField(f, current)
        }
    }

    private func stringField(_ f: WidgetSettingFieldInfo, _ current: JSONValue?) -> some View {
        labeled(f.label) {
            TextField(f.label, text: Binding(get: { current?.stringValue ?? "" }, set: { setting(f.key, .string($0)) }))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.dsCaption).foregroundStyle(.secondary)
            content()
        }
    }
}

typealias WidgetSettingFieldInfo = WidgetSettingField

/// «Text size»: Auto (максимальный кегль, который влезает) или ручной множитель 25–400 %.
struct FontWeightRow: View {
    let choice: FontChoice
    @Binding var weight: String?

    private static let options: [(key: String, name: String, w: Font.Weight)] = [
        ("ultraLight", "Ultra Light", .ultraLight), ("thin", "Thin", .thin), ("light", "Light", .light),
        ("regular", "Regular", .regular), ("medium", "Medium", .medium), ("semibold", "Semibold", .semibold),
        ("bold", "Bold", .bold), ("heavy", "Heavy", .heavy), ("black", "Black", .black)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Weight").font(.dsBody)
            FlowLayout(spacing: 6) {
                chip(selected: weight == nil, help: "Auto: the widget's own weights", label: "Weight: Auto") {
                    Text("Auto").font(.system(size: 13, weight: .medium))
                } action: { weight = nil }
                ForEach(Self.options, id: \.key) { o in
                    let exact = choice.family.map { FontResolver.hasExactWeight(family: $0, weight: o.w) } ?? true
                    chip(selected: weight?.lowercased() == o.key.lowercased(),
                         help: exact ? o.name : "\(o.name). Closest available weight is used",
                         label: "Weight: \(o.name)") {
                        Text("Aa").font(choice.font(size: 15, weight: o.w))
                    } action: { weight = o.key }
                    .opacity(exact ? 1 : 0.55)
                }
            }
        }
    }

    private func chip<C: View>(selected: Bool, help: String, label: String, @ViewBuilder content: () -> C,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(minWidth: 34)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(selected ? DS.accent.opacity(0.32) : Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(selected ? DS.accent : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TextSizeRow: View {
    @Binding var scale: Double?
    @State private var text = ""
    @FocusState private var focused: Bool

    static let range = 0.25...4.0
    private var percent: Double { ((scale ?? 1) * 100).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SettingRow(label: "Text size") {
                Picker("Text size mode", selection: Binding(
                    get: { scale != nil }, set: { manual in scale = manual ? (scale ?? 1) : nil })) {
                    Text("Auto").tag(false)
                    Text("Manual").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .accessibilityLabel("Text size mode")
            }
            if scale != nil {
                HStack(spacing: DS.Space.xs) {
                    TextField("Percent", text: $text)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .frame(width: 72).focused($focused)
                        .onSubmit(commit)
                        .onChange(of: focused) { _, f in if !f { commit() } }
                        .accessibilityLabel("Text size percent")
                    Text("%").foregroundStyle(.secondary)
                    Stepper("Text size step", value: Binding(
                        get: { percent }, set: { set($0 / 100) }), in: 25...400, step: 5)
                        .labelsHidden().accessibilityLabel("Text size step")
                    Spacer(minLength: 0)
                }
                Slider(value: Binding(get: { min(percent, 300) }, set: { set($0 / 100) }), in: 25...300, step: 5) {
                    Text("Text size")
                }
                .labelsHidden().accessibilityLabel("Text size")
            }
            Text("Auto fills the widget with the largest text that fits.")
                .font(.dsCaption).foregroundStyle(.secondary)
        }
        .onAppear(perform: sync)
        .onChange(of: scale) { _, _ in if !focused { sync() } }
    }

    private func sync() { text = "\(Int(percent))" }

    private func set(_ v: Double) {
        scale = min(max(v, Self.range.lowerBound), Self.range.upperBound)
        sync()
    }

    private func commit() {
        let digits = text.filter { $0.isNumber || $0 == "." }
        if let v = Double(digits) { set(v / 100) } else { sync() }
    }
}
