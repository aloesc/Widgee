import AppKit
import SwiftUI

/// Карточка «О приложении» для раздела Settings.
struct AboutView: View {
    private var version: String {
        let i = Bundle.main.infoDictionary
        return "Version \(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        CardSection(title: "About", symbol: "info.circle.fill", tint: .gray) {
            VStack(spacing: DS.Space.s) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4).accessibilityHidden(true)
                Text("Widgee").font(.dsTitle)
                Text(version).font(.dsBody).foregroundStyle(.secondary)
                HStack(spacing: DS.Space.xs) {
                    Chip(text: "Open source, GPL-3.0", tint: .green, symbol: "checkmark.seal.fill")
                    Button("License") { AppLinks.open(AppLinks.license) }.buttonStyle(.widgeeSecondary)
                }
                HStack(spacing: DS.Space.xs) {
                    Button { AppLinks.open(AppLinks.repository) } label: { Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                        .buttonStyle(.widgeeSecondary)
                    Button { AppLinks.open(AppLinks.issues) } label: { Label("Report an Issue", systemImage: "exclamationmark.bubble") }
                        .buttonStyle(.widgeeSecondary)
                }
                Button { AppLinks.open(AppLinks.donate) } label: {
                    Text("Support the Developer ❤️").frame(maxWidth: .infinity)
                }
                .buttonStyle(.widgeePrimary).controlSize(.large)
                .padding(.top, DS.Space.xs)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Раздел Settings главного окна.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var launch: LaunchAtLogin

    private let shortcuts: [(keys: [String], text: String)] = [
        (["⌥"], "Hold while dragging to turn snapping off temporarily"),
        (["⌘", "N"], "Create Widget"),
        (["⌘", "G"], "Gallery"),
        (["⌘", "E"], "Edit Mode"),
    ]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: DS.Space.m) {
                VStack(spacing: DS.Space.m) {
                    CardSection(title: "General", symbol: "gearshape.fill", tint: .gray) {
                        Toggle(isOn: Binding(get: { launch.isEnabled }, set: { launch.set($0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login").font(.dsBody)
                                Text("Widgets appear on your desktop right after you sign in.").font(.dsCaption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        Divider()
                        SettingRow(label: "Widgets folder") {
                            Button { state.openWidgetsFolder() } label: { Label("Open Widgets Folder", systemImage: "folder") }
                                .buttonStyle(.widgeeSecondary)
                        }
                    }
                    CardSection(title: "Shortcuts", symbol: "command", tint: .indigo) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, s in
                                HStack(spacing: DS.Space.s) {
                                    HStack(spacing: 4) { ForEach(s.keys, id: \.self) { KeyCap(text: $0) } }
                                        .frame(width: 84, alignment: .leading)
                                    Text(s.text).font(.dsBody).foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(s.keys.joined(separator: " ")): \(s.text)")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                AboutView().frame(width: 340)
            }
            .padding(.vertical, DS.Space.xs).padding(.bottom, DS.Space.l)
        }
        .scrollClipDisabled()
    }
}
