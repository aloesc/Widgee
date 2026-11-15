import SwiftUI
import WidgeeCore

/// Строит нативный SwiftUI из декларативного дерева `UINode`.
/// Неизвестные `type` и превышение глубины дают плейсхолдер, без краша.
public struct WidgetTreeView: View {
    public nonisolated static let maxDepth = 24
    /// Имена поддерживаемых компонентов.
    public nonisolated static let knownTypes: Set<String> = [
        "VStack", "HStack", "ZStack", "Spacer", "Text", "Image", "LinearBar", "Ring", "Gauge",
        "SegmentedBar", "Sparkline", "LineChart", "BarChart", "DigitalClock", "AnalogClock",
    ]

    public var node: UINode
    public var theme: Theme
    public var sizeClass: SizeClass

    public init(node: UINode, theme: Theme = Theme(), sizeClass: SizeClass = .medium) {
        self.node = node
        self.theme = theme
        self.sizeClass = sizeClass
    }

    public var body: some View {
        NodeView(node: node, ctx: RenderContext(theme: theme, sizeClass: sizeClass), depth: 0)
    }
}

struct NodeView: View {
    let node: UINode
    let ctx: RenderContext
    let depth: Int

    var body: some View {
        if depth > WidgetTreeView.maxDepth {
            PlaceholderView(label: "depth limit")
        } else {
            content.modifier(CommonProps(p: Props(node.props), frameAlignment: frameAlignment))
        }
    }

    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, c in
            NodeView(node: c, ctx: ctx, depth: depth + 1)
        }
    }

    /// Рамка width/height по умолчанию центрирует блок. Если у VStack/ZStack явно задан `alignment`,
    /// блок прижимается в рамке в ту же сторону: иначе стек, ужатый по содержимому, выравнивал бы
    /// элементы только внутри себя и оставался по центру окна.
    private var frameAlignment: Alignment {
        let p = Props(node.props)
        guard let a = p.string("alignment") else { return .center }
        switch node.type {
        case "VStack":
            switch a { case "leading": return .leading; case "trailing": return .trailing; default: return .center }
        case "ZStack": return zAlign(a)
        default: return .center
        }
    }

    @ViewBuilder private var content: some View {
        let p = Props(node.props)
        switch node.type {
        case "VStack":
            VStack(alignment: hAlign(p.string("alignment")), spacing: p.length("spacing")) { children }
        case "HStack":
            HStack(alignment: vAlign(p.string("alignment")), spacing: p.length("spacing")) { children }
        case "ZStack":
            ZStack(alignment: zAlign(p.string("alignment"))) { children }
        case "Spacer":
            if let m = p.length("minLength") { Spacer(minLength: m) } else { Spacer() }
        case "Text":
            textView(p)
        case "Image":
            imageView(p)
        case "LinearBar": LinearBarView(p: p, ctx: ctx)
        case "Ring": RingView(p: p, ctx: ctx, content: children)
        case "Gauge": GaugeView(p: p, ctx: ctx, content: children)
        case "SegmentedBar": SegmentedBarView(p: p, ctx: ctx)
        case "Sparkline": SparklineView(p: p, ctx: ctx)
        case "LineChart": LineChartView(p: p, ctx: ctx)
        case "BarChart": BarChartView(p: p, ctx: ctx)
        case "DigitalClock": DigitalClockView(p: p, ctx: ctx)
        case "AnalogClock": AnalogClockView(p: p, ctx: ctx)
        default: PlaceholderView(label: "Unknown component \(node.type)")
        }
    }

    @ViewBuilder private func textView(_ p: Props) -> some View {
        let size = p.length("size") ?? 14 * ctx.scale
        let t = Text(p.string("text") ?? "")
            .font(ctx.font(size: size, weight: parseWeight(p.string("weight"))))
            .foregroundStyle(ctx.color(p.string("color")))
            .multilineTextAlignment(textAlign(p.string("align")))
        if p.bool("monospacedDigit") ?? false {
            t.monospacedDigit().lineLimit(p.int("lineLimit", in: 1...50))
        } else {
            t.lineLimit(p.int("lineLimit", in: 1...50))
        }
    }

    @ViewBuilder private func imageView(_ p: Props) -> some View {
        let size = p.length("size") ?? 16 * ctx.scale
        Image(systemName: p.string("systemName") ?? "questionmark.square.dashed")
            .font(.system(size: size, weight: parseWeight(p.string("weight"))))
            .foregroundStyle(ctx.color(p.string("color")))
    }
}

/// Общие props: padding, width, height, opacity.
struct CommonProps: ViewModifier {
    let p: Props
    var frameAlignment: Alignment = .center
    func body(content: Content) -> some View {
        content
            .padding(p.length("padding") ?? 0)
            .frame(width: p.length("width"), height: p.length("height"), alignment: frameAlignment)
            .opacity(p.double("opacity").map { Props.clamp01($0) } ?? 1)
    }
}

private func hAlign(_ s: String?) -> HorizontalAlignment {
    switch s { case "center": .center; case "trailing": .trailing; default: .leading }
}
private func vAlign(_ s: String?) -> VerticalAlignment {
    switch s { case "top": .top; case "bottom": .bottom; default: .center }
}
private func zAlign(_ s: String?) -> Alignment {
    switch s {
    case "leading": .leading; case "trailing": .trailing; case "top": .top; case "bottom": .bottom
    case "topLeading": .topLeading; case "topTrailing": .topTrailing
    case "bottomLeading": .bottomLeading; case "bottomTrailing": .bottomTrailing
    default: .center
    }
}
private func textAlign(_ s: String?) -> TextAlignment {
    switch s { case "center": .center; case "trailing": .trailing; default: .leading }
}
