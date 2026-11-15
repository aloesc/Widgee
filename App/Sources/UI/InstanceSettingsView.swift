import Background
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
                            Picker("Font", selection: binding(inst, \.fontDesign)) {
                                Text("SF Pro").tag(FontDesign.standard)
                                Text("Rounded").tag(FontDesign.rounded)
                                Text("Mono").tag(FontDesign.monospaced)
                            }.labelsHidden().fixedSize()
                        }
                        SettingRow(label: "Text appearance") {
                            Picker("Text appearance", selection: Binding(
                                get: { inst.textAppearance ?? .auto }, set: { v in state.update(id) { $0.textAppearance = v == .auto ? nil : v } })) {
                                Text("Auto").tag(TextAppearance.auto)
                                Text("Light (dark text)").tag(TextAppearance.light)
                                Text("Dark (light text)").tag(TextAppearance.dark)
                            }.labelsHidden().fixedSize()
                        }
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
