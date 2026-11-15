import SwiftUI

/// Дизайн-система Widgee: токены, акценты разделов и базовые компоненты.
/// Тема следует системе; компоненты учитывают Reduce Motion / Reduce Transparency / Increase Contrast.
enum DS {
    /// Акцент системы, фиксированный синий, не тускнеет в неактивном окне.
    static var accent: Color { Color(red: 0.04, green: 0.52, blue: 1.0) }
    enum Space {
        static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32
    }
    enum Radius {
        static let small: CGFloat = 10, medium: CGFloat = 14, large: CGFloat = 20, xlarge: CGFloat = 28
    }
}

/// Типографика на системных текстовых стилях (масштабируется вместе с системой).
extension Font {
    static var dsLargeTitle: Font { .system(.largeTitle, design: .rounded).weight(.bold) }
    static var dsTitle: Font { .system(.title2, design: .rounded).weight(.semibold) }
    static var dsHeadline: Font { .system(.title3).weight(.semibold) }
    static var dsBody: Font { .body }
    static var dsCaption: Font { .caption }
}

// MARK: акценты разделов

extension GalleryCategory {
    var tint: Color {
        switch self {
        case .all: DS.accent
        case .today: .red
        case .weather: .cyan
        case .battery: .green
        case .clock: .orange
        case .system: .purple
        case .other: .gray
        }
    }
}

extension MainSection {
    var tint: Color {
        switch self {
        case .gallery: .blue
        case .mine: .indigo
        case .create: .pink
        case .layout: .teal
        case .settings: .gray
        }
    }
}

// MARK: компоненты

/// Иконка боковой панели: цветной скруглённый квадрат с символом (как в System Settings).
struct SidebarIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Заголовок раздела: крупный заголовок и подзаголовок.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(.dsLargeTitle)
                if let subtitle { Text(subtitle).font(.dsBody).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            accessory
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Подзаголовок группы (например, категория в списке плиток).
struct GroupHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    var count: Int?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            SidebarIcon(symbol: symbol, tint: tint, size: 22)
            Text(title).font(.dsHeadline)
            if let count { Text("\(count)").font(.dsCaption.monospacedDigit()).foregroundStyle(.secondary) }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Карточка: материал, тонкая обводка, мягкая тень; при наведении слегка поднимается.
struct GlassCard<Content: View>: View {
    var selected = false
    var tint: Color = DS.accent
    var radius: CGFloat = DS.Radius.large
    var interactive = true
    @ViewBuilder var content: Content
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let lifted = hover && interactive
        content
            .background {
                if reduceTransparency { shape.fill(Color(nsColor: .controlBackgroundColor)) }
                else { shape.fill(.regularMaterial) }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : (scheme == .dark ? 0.14 : 0.1)), lineWidth: 1)
            }
            .overlay {
                if selected { shape.strokeBorder(tint, lineWidth: 3).padding(-1.5) }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(lifted ? 0.28 : 0.14), radius: lifted ? 18 : 8, y: lifted ? 8 : 3)
            .scaleEffect(lifted && !reduceMotion ? 1.02 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.25), value: lifted)
            .onHover { hover = $0 }
            .contentShape(shape)
    }
}

/// Небольшая метка (категория, вариант).
struct Chip: View {
    let text: String
    var tint: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.dsCaption.weight(.medium))
        }
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
        .padding(.horizontal, DS.Space.xs).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Бейдж с размером в ячейках («2×1»).
struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.dsCaption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Основная кнопка (акцентная заливка), не зависит от активности окна.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = DS.accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.xs)
            .frame(minHeight: 32)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.75 : 1)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

/// Вторичная кнопка (нейтральная заливка и обводка).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.xs)
            .frame(minHeight: 32)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.09)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.15), lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var widgeePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var widgeeSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: компоненты страниц

/// Секция-карточка: заголовок с цветной иконкой и содержимое (замена серой Form).
struct CardSection<Content: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = DS.accent
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(interactive: false) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(spacing: DS.Space.xs) {
                    if let symbol { SidebarIcon(symbol: symbol, tint: tint, size: 22) }
                    Text(title).font(.dsHeadline)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Строка «подпись слева, элемент управления справа».
struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(label).font(.dsBody)
            Spacer(minLength: DS.Space.xs)
            content
        }
    }
}

/// Слайдер с подписью и текущим значением над ним.
struct SliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    let step: V.Stride
    let format: (V) -> String

    /// Без явного `step` шаг зависит от диапазона: для коротких (0…1) 0,01, иначе 1.
    /// Раньше по умолчанию был 1, и ползунок 0…1 принимал только 0 и 1.
    init(_ label: String, value: Binding<V>, in range: ClosedRange<V>, step: V.Stride? = nil,
         format: @escaping (V) -> String = { "\(Int($0)) pt" }) {
        self.label = label; self._value = value; self.range = range
        self.step = step ?? (range.upperBound - range.lowerBound <= 2 ? 0.01 : 1)
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.dsBody)
                Spacer()
                Text(format(value)).font(.dsBody.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $value, in: range, step: step) { Text(label) }
                .labelsHidden()
                .accessibilityLabel(label)
                .accessibilityValue(format(value))
        }
    }
}

/// «Кейкап» клавиши.
struct KeyCap: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 8)
            .frame(minWidth: 30, minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.6 : 0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1.5)
    }
}

/// Деструктивная кнопка (красный акцент).
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody.weight(.medium))
            .foregroundStyle(Color.red)
            .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.xs)
            .frame(minHeight: 32)
            .background(Capsule().fill(Color.red.opacity(configuration.isPressed ? 0.28 : 0.13)))
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

/// Пустое состояние: крупный символ на подложке, заголовок, пояснение и действие.
struct EmptyStateView<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = DS.accent
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                Circle().fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 128, height: 128)
                Circle().strokeBorder(tint.opacity(0.3), lineWidth: 1).frame(width: 128, height: 128)
                Image(systemName: symbol).font(.system(size: 52, weight: .medium)).foregroundStyle(tint)
            }
            .accessibilityHidden(true)
            Text(title).font(.dsTitle)
            Text(message).font(.dsBody).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            action
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Раскладка с переносом строк (для чипов).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Без заданной ширины (ideal-замер внутри ScrollView) не раскладываем всё в одну строку:
        // иначе контейнер получает ширину в сотни pt и выпирает за панель. Берём ширину самого широкого элемента.
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let maxW = (proposal.width.map { $0.isFinite ? $0 : widest }) ?? widest
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); w = max(w, x - spacing)
        }
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
