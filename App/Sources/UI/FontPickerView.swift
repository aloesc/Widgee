import AppKit
import Renderer
import SwiftUI
import WidgeeCore

/// Выбор шрифта: либо системный дизайн (`fontFamily == nil`), либо семейство установленного шрифта.
struct FontChoice: Equatable {
    var design: FontDesign = .standard
    var family: String?

    var displayName: String {
        if let family { return family }
        switch design {
        case .standard: return "SF Pro"
        case .rounded: return "Rounded"
        case .monospaced: return "Mono"
        case .serif: return "Serif"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Начертание подбираем по весу: `.custom(family)` без него у Futura/Gill Sans берёт полужирное.
        if let family, let ps = FontResolver.postScriptName(family: family, weight: weight) { return .custom(ps, fixedSize: size) }
        switch design {
        case .standard: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        }
    }
}

private enum FontCatalog {
    static let recommended = ["Helvetica Neue", "Avenir Next", "Avenir", "Futura", "Gill Sans", "Optima", "Georgia", "Palatino",
                              "Baskerville", "Didot", "Hoefler Text", "Times New Roman", "American Typewriter", "Menlo", "SF Mono",
                              "Courier New", "Monaco", "Marker Felt", "Chalkduster", "Noteworthy", "Bradley Hand", "Savoye LET",
                              "Papyrus", "Copperplate", "Trebuchet MS", "Verdana"]
    static let system: [FontChoice] = [FontDesign.standard, .rounded, .monospaced, .serif].map { FontChoice(design: $0, family: nil) }
    @MainActor static let all: [String] = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
    @MainActor static let installedRecommended: [String] = recommended.filter { FontResolver.isInstalled($0) }
}

/// Кнопка-«поле»: название текущего шрифта его же шрифтом + шеврон; по клику открывает список.
struct FontPickerButton: View {
    @Binding var choice: FontChoice
    @State private var shown = false
    @State private var hover = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: DS.Space.xs) {
                Text(choice.displayName).font(choice.font(size: 13)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 5)
            .frame(minWidth: 150, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.small).fill(Color.primary.opacity(hover ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.small)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.15), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Font: \(choice.displayName)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            FontListView(choice: $choice) { shown = false }
        }
    }
}

/// Содержимое поповера: поиск, секции System / Recommended / All fonts, каждая строка своим шрифтом.
struct FontListView: View {
    @Binding var choice: FontChoice
    var onDismiss: () -> Void = {}
    @State private var query = ""
    @State private var cursor: String?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Item: Identifiable {
        let id: String
        let choice: FontChoice
    }
    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [Item]
    }

    private var sections: [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        func match(_ s: String) -> Bool { q.isEmpty || s.localizedCaseInsensitiveContains(q) }
        let sys = FontCatalog.system.filter { match($0.displayName) }.map { Item(id: "sys:\($0.design.rawValue)", choice: $0) }
        let rec = FontCatalog.installedRecommended.filter(match).map { Item(id: "rec:\($0)", choice: FontChoice(design: choice.design, family: $0)) }
        let all = FontCatalog.all.filter(match).map { Item(id: "all:\($0)", choice: FontChoice(design: choice.design, family: $0)) }
        return [Section(id: "System", title: "System", items: sys), Section(id: "Recommended", title: "Recommended", items: rec),
                Section(id: "All fonts", title: "All fonts", items: all)].filter { !$0.items.isEmpty }
    }

    private func isSelected(_ c: FontChoice) -> Bool {
        c.family == choice.family && (c.family != nil || c.design == choice.design)
    }

    private func pick(_ c: FontChoice) {
        // Для семейства дизайн сохраняем как фолбэк, для системных вариантов — выбираем дизайн.
        choice = c.family == nil ? c : FontChoice(design: choice.design, family: c.family)
    }

    private func move(_ delta: Int, _ ids: [String]) {
        guard !ids.isEmpty else { return }
        let cur = cursor.flatMap { ids.firstIndex(of: $0) } ?? -1
        cursor = ids[min(max(cur + delta, 0), ids.count - 1)]
    }

    var body: some View {
        let secs = sections
        let flat = secs.flatMap(\.items)
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search fonts", text: $query).textFieldStyle(.plain).focused($focused)
                    .accessibilityLabel("Search fonts")
                    .onSubmit { if let c = flat.first(where: { $0.id == cursor }) ?? flat.first { pick(c.choice) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(secs) { sec in
                            SwiftUI.Section {
                                ForEach(sec.items) { item in
                                    FontRow(choice: item.choice, selected: isSelected(item.choice),
                                            highlighted: cursor == item.id) { pick(item.choice) }
                                        .id(item.id)
                                }
                            } header: {
                                Text(sec.title).font(.dsCaption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, DS.Space.s).padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                        if secs.isEmpty {
                            Text("No fonts found").font(.dsBody).foregroundStyle(.secondary).padding(DS.Space.m)
                        }
                    }
                }
                .onChange(of: cursor) { _, id in
                    guard let id else { return }
                    if reduceMotion { proxy.scrollTo(id) } else { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                }
            }
            Divider()
            HStack {
                Button("Reset to default") { choice = FontChoice() }
                    .buttonStyle(.plain).foregroundStyle(choice == FontChoice() ? Color.secondary : DS.accent)
                    .disabled(choice == FontChoice())
                Spacer()
            }
            .font(.dsCaption).padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
        }
        .frame(width: 320, height: 420)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.clear))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1, flat.map(\.id)); return .handled }
        .onKeyPress(.upArrow) { move(-1, flat.map(\.id)); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.return) {
            if let c = flat.first(where: { $0.id == cursor }) { pick(c.choice); return .handled }
            return .ignored
        }
    }
}

private struct FontRow: View {
    let choice: FontChoice
    let selected: Bool
    let highlighted: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).opacity(selected ? 1 : 0).frame(width: 12)
                    .foregroundStyle(DS.accent)
                Text(choice.displayName).font(choice.font(size: 15)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: DS.Space.xs)
                Text("Aa 0123").font(choice.font(size: 12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, DS.Space.s).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover || highlighted ? 0.1 : 0)).padding(.horizontal, 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Font: \(choice.displayName)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
