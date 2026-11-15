import AppKit
import SwiftUI
import AgentPrompt

struct CreateWidgetView: View {
    let widgetsDirectory: URL
    let openFolder: () -> Void
    @State private var request = ""
    @State private var prompt = ""
    @State private var copied = false
    @State private var expanded = false
    @State private var debounce: Task<Void, Never>?

    private var isEmpty: Bool { request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private let ideas: [(String, String)] = [
        ("CPU & RAM rings", "cpu"), ("Weather for my city", "cloud.sun.fill"),
        ("Pomodoro timer", "timer"), ("Battery level", "battery.75percent"),
        ("Next calendar event", "calendar"), ("World clock", "globe"),
    ]

    private var step: Int { copied ? 3 : (isEmpty ? 1 : 2) }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.m) {
                steps
                HStack(alignment: .top, spacing: DS.Space.m) {
                    describeCard.frame(maxWidth: .infinity)
                    promptCard.frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, DS.Space.xs).padding(.bottom, DS.Space.l)
        }
        .scrollClipDisabled()
        .onAppear { rebuild() }
        .onChange(of: request) {
            copied = false
            debounce?.cancel()
            debounce = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { rebuild() }
            }
        }
    }

    // MARK: шаги

    private var steps: some View {
        let items = ["Describe", "Copy", "Paste into your AI agent", "Widget appears here"]
        return GlassCard(interactive: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                    let n = i + 1, done = n < step, current = n == step
                    HStack(spacing: DS.Space.xs) {
                        ZStack {
                            Circle().fill(done || current ? MainSection.create.tint : Color.primary.opacity(0.1))
                            if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                            else { Text("\(n)").font(.dsCaption.weight(.bold)).foregroundStyle(current ? Color.white : Color.secondary) }
                        }
                        .frame(width: 24, height: 24)
                        Text(text).font(.dsBody.weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? Color.primary : Color.secondary).lineLimit(2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(n): \(text)")
                    .accessibilityAddTraits(current ? .isSelected : [])
                    if n < items.count {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(DS.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: описание

    private var describeCard: some View {
        CardSection(title: "What do you want your widget to show?", symbol: "text.bubble.fill", tint: MainSection.create.tint) {
            TextEditor(text: $request)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(alignment: .topLeading) {
                    if request.isEmpty {
                        Text("For example: a small widget with my CPU and RAM usage as two rings")
                            .font(.system(size: 14)).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 8)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .accessibilityLabel("Widget description")
            Text("Need an idea?").font(.dsCaption).foregroundStyle(.secondary)
            FlowLayout(spacing: DS.Space.xs) {
                ForEach(ideas, id: \.0) { idea in
                    Button { request = idea.0 } label: {
                        Chip(text: idea.0, tint: MainSection.create.tint, symbol: idea.1)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use idea: \(idea.0)")
                }
            }
        }
    }

    // MARK: промт

    private var promptCard: some View {
        CardSection(title: "Prompt for your AI agent", symbol: "terminal.fill", tint: .indigo) {
            ScrollView {
                Text(prompt)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: expanded ? 360 : 180)
            .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .overlay(alignment: .bottomTrailing) {
                Button { expanded.toggle() } label: {
                    Label(expanded ? "Collapse" : "Expand", systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly).padding(6)
                }
                .buttonStyle(.plain).padding(6).help(expanded ? "Collapse prompt" : "Expand prompt")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.widgeePrimary).controlSize(.large).disabled(isEmpty)
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(widgetsDirectory.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 0)
                Button("Open widgets folder", action: openFolder).buttonStyle(.widgeeSecondary)
            }
        }
    }

    private func rebuild() {
        prompt = AgentPromptBuilder.build(request: request, widgetsDirectory: widgetsDirectory.path)
    }
}
