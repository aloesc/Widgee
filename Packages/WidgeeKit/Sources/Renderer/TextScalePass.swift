import SwiftUI
import WidgeeCore

/// Ручной «Text size» (`Theme.textScale`). Раскладку виджет строит одну и ту же (коробки `fit` и размеры `size`),
/// а процент применяет хост, измеряя текст настоящим шрифтом и весом:
/// - до 100 %: текст в коробках и обычный текст просто мельче;
/// - выше 100 %: главная коробка стека растёт за счёт второстепенных (пока строке хватает ширины),
///   обычный текст растёт до потолка, после которого он вылез бы из своего контейнера.
/// Суммарная высота коробок не меняется, поэтому текст не обрезается краем виджета.
@MainActor
struct TextScalePass {
    struct Result {
        var node: UINode
        /// Множитель `size` обычного текста.
        var plain: CGFloat = 1
        /// Множитель кегля, вписанного в коробку `fit`.
        var fit: CGFloat = 1
    }

    /// Коробка ниже этой высоты (pt) нечитаема: ряд убирается, место уходит главной коробке.
    static let minBox: CGFloat = 10
    /// Главная коробка должна быть выше остальных хотя бы во столько раз (ряды списков и сеток равны и не трогаются).
    static let dominance: CGFloat = 1.25
    /// Процент, на котором достигается потолок роста.
    static let fullRange: CGFloat = 3

    let metrics: TextMetrics
    /// Масштаб размеров по умолчанию (`RenderContext.scale`): рендер умножает на него `size`, когда тот не задан.
    var defaults: CGFloat = 1

    static func run(_ root: UINode, theme: Theme, defaults: CGFloat = 1) -> Result {
        guard let s = theme.textScale, s.isFinite else { return Result(node: root) }
        let m = CGFloat(min(max(s, 0.25), 4))
        guard m > 1 else { return Result(node: root, plain: m, fit: m) }
        let pass = TextScalePass(metrics: TextMetrics(theme: theme), defaults: defaults)
        let node = pass.grow(root, by: m)
        return Result(node: node, plain: pass.ceiling(node, upTo: m))
    }

    // MARK: коробки fit

    static func fitBox(_ n: UINode) -> CGSize? {
        guard n.type == "Text" || n.type == "DigitalClock" else { return nil }
        let p = Props(n.props)
        guard p.bool("fit") ?? false, let w = p.length("width"), let h = p.length("height"), w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Главная коробка ряда: сам fit-текст или самый высокий fit-текст внутри HStack/ZStack без собственной высоты.
    private func mainBox(_ n: UINode) -> UINode? {
        if Self.fitBox(n) != nil { return n }
        guard n.type == "HStack" || n.type == "ZStack", Props(n.props).length("height") == nil else { return nil }
        return n.children.compactMap(mainBox).max { (Self.fitBox($0)?.height ?? 0) < (Self.fitBox($1)?.height ?? 0) }
    }

    /// Высота, до которой коробку есть смысл растить: дальше строка упирается в ширину.
    private func usefulHeight(_ n: UINode, box: CGSize) -> CGFloat {
        let t = TextSpec(n)
        let w = metrics.width(t.text, size: box.height / 1.2, weight: t.weight, monospaced: t.monospaced, monospacedDigit: t.monospacedDigit)
        return w > 0 ? box.height * box.width / w : box.height
    }

    private func scaleBoxes(_ n: UINode, by k: CGFloat) -> UINode {
        var n = n
        if let box = Self.fitBox(n) {
            n.props["height"] = .number(Double(box.height * k))
        } else if n.type == "HStack" || n.type == "ZStack" {
            n.children = n.children.map { scaleBoxes($0, by: k) }
        }
        return n
    }

    func grow(_ node: UINode, by m: CGFloat) -> UINode {
        var n = node
        if n.type == "VStack" { n.children = redistribute(n.children, by: m) }
        n.children = n.children.map { grow($0, by: m) }
        return n
    }

    private func redistribute(_ children: [UINode], by m: CGFloat) -> [UINode] {
        let rows: [(index: Int, main: UINode, box: CGSize)] = children.enumerated().compactMap { i, c in
            guard let main = mainBox(c), let box = Self.fitBox(main) else { return nil }
            return (i, main, box)
        }
        guard let tallest = rows.map(\.box.height).max() else { return children }
        // Главные ряды: самые высокие (равные растут вместе). Остальные им уступают.
        let primary = rows.filter { $0.box.height * Self.dominance > tallest }
        let others = rows.filter { $0.box.height * Self.dominance <= tallest }
        guard !others.isEmpty else { return children }
        let total = rows.reduce(0) { $0 + $1.box.height }
        let primarySum = primary.reduce(0) { $0 + $1.box.height }
        let widthLimit = primary.map { usefulHeight($0.main, box: $0.box) / $0.box.height }.min() ?? 1
        let g = Self.eased(m, limit: min(widthLimit, total / primarySum))
        guard g > 1.02 else { return children }
        let left = total - primarySum * g
        let k = left / (total - primarySum)
        let kept = others.filter { $0.box.height * k >= Self.minBox }
        let keptSum = kept.reduce(0) { $0 + $1.box.height }
        let k2 = keptSum > 0 ? min(1, left / keptSum) : 0
        let grown = Set(primary.map(\.index)), keep = Set(kept.map(\.index)), all = Set(others.map(\.index))
        return children.enumerated().compactMap { i, c in
            if grown.contains(i) { return scaleBoxes(c, by: g) }
            guard all.contains(i) else { return c }
            return keep.contains(i) ? scaleBoxes(c, by: k2) : nil
        }
    }

    /// Множитель для процента m > 1 при потолке `limit`. Пока места хватает, это сам процент;
    /// иначе диапазон 100...300 % плавно покрывает весь запас, чтобы ползунок работал до конца, а не упирался в начале.
    static func eased(_ m: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 1 else { return 1 }
        return min(m, 1 + (min(limit, max(m, fullRange)) - 1) * min(1, (m - 1) / (fullRange - 1)))
    }

    // MARK: потолок обычного текста

    /// Множитель обычного текста с учётом `lineLimit`. Абзац с лимитом строк больше одной виджет уже подогнал
    /// под свою область: если его увеличить, хвост усечётся до «…», поэтому он только уменьшается.
    static func plainScale(_ x: CGFloat, lineLimit: Int?) -> CGFloat {
        (lineLimit ?? 1) > 1 ? min(x, 1) : x
    }

    /// Множитель обычного текста для процента m: не больше того, при котором текст вылез бы из контейнера
    /// с заданной высотой (сильнее, чем уже вылезал при 100 %).
    func ceiling(_ root: UINode, upTo m: CGFloat) -> CGFloat {
        let availW = Props(root.props).length("width") ?? .infinity
        func excess(_ x: CGFloat) -> [CGFloat] {
            var out: [CGFloat] = []
            _ = need(root, x, availW, &out)
            return out
        }
        let base = excess(1)
        func ok(_ x: CGFloat) -> Bool { zip(excess(x), base).allSatisfy { $0 <= $1 + 0.5 } }
        var lo: CGFloat = 1, hi = max(m, Self.fullRange)
        if ok(hi) { return m }
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if ok(mid) { lo = mid } else { hi = mid }
        }
        return Self.eased(m, limit: lo)
    }

    /// Оценка высоты узла при множителе x; превышения над заданными высотами копятся в `out` (порядок обхода стабилен).
    private func need(_ n: UINode, _ x: CGFloat, _ availW: CGFloat, _ out: inout [CGFloat]) -> CGFloat {
        let p = Props(n.props)
        if let box = Self.fitBox(n) { return box.height }
        let pad = p.length("padding") ?? 0
        let inner = (p.length("width") ?? availW) - pad * 2
        var content: CGFloat = 0
        // Строке текста с собственной высотой прощаем небольшой вылет: глифы занимают меньше высоты линии.
        var slack: CGFloat = 1
        switch n.type {
        case "VStack":
            let hs = n.children.map { need($0, x, inner, &out) }
            content = hs.reduce(0, +) + (p.length("spacing") ?? 8) * CGFloat(max(0, hs.count - 1))
        case "HStack", "ZStack":
            content = n.children.map { need($0, x, inner, &out) }.max() ?? 0
        case "Spacer":
            content = p.length("minLength") ?? 0
        case "Text":
            let t = TextSpec(n)
            let limit = p.int("lineLimit", in: 1...50)
            let size = (p.length("size") ?? 14 * defaults) * Self.plainScale(x, lineLimit: limit)
            var lines = 1
            let lineHeight = metrics.lineHeight(size: size, weight: t.weight)
            if limit != 1 {
                let width = metrics.width(t.text, size: size, weight: t.weight, monospacedDigit: t.monospacedDigit)
                let wrap = inner.isFinite && inner > 0 ? Int((width / inner).rounded(.up)) : 1
                lines = min(max(wrap, t.text.split(separator: "\n", omittingEmptySubsequences: false).count), limit ?? 50)
                // Строка без lineLimit в колонке заданной ширины не сжимается, а переносится: шире колонки ей расти нельзя.
                if limit == nil, let own = p.length("width") { out.append(max(0, width - (own - pad * 2))) }
            }
            content = lineHeight * CGFloat(lines)
            slack = 1.25
        case "DigitalClock":
            content = metrics.lineHeight(size: (p.length("size") ?? 32 * defaults) * x, weight: parseWeight(p.string("weight") ?? "medium"),
                                         monospaced: p.bool("monospaced") ?? false)
            slack = 1.25
        case "Image":
            content = (p.length("size") ?? 16 * defaults) * 1.2
        case "Ring", "Gauge":
            // Содержимое рисуется поверх кольца: ему доступна только внутренняя часть.
            let size = p.length("size") ?? (n.type == "Ring" ? 56 : 80) * defaults
            let room = n.type == "Ring" ? size * 0.7 : size * 0.45
            let c = n.children.map { need($0, x, room, &out) }.max() ?? 0
            out.append(max(0, c - room))
            return n.type == "Ring" ? size : size / 2
        case "AnalogClock":
            content = p.length("size") ?? 100 * defaults
        default:
            break
        }
        let total = content + pad * 2
        guard let h = p.length("height") else { return total }
        out.append(max(0, total - h * slack))
        return h
    }
}

/// Текст, шрифт и вес узла `Text`/`DigitalClock` в том виде, в котором их рисует рендерер.
@MainActor
struct TextSpec {
    var text: String
    var weight: Font.Weight
    var monospaced = false
    var monospacedDigit = false

    init(text: String, weight: Font.Weight, monospaced: Bool = false, monospacedDigit: Bool = false) {
        self.text = text; self.weight = weight; self.monospaced = monospaced; self.monospacedDigit = monospacedDigit
    }

    init(_ n: UINode) {
        let p = Props(n.props)
        if n.type == "DigitalClock" {
            text = DigitalClockView.format(.now, timeZone: resolveTimeZone(p.string("timeZone")), hour12: p.bool("hour12") ?? false,
                                           seconds: p.bool("showSeconds") ?? false, part: p.string("part") ?? "all")
            weight = parseWeight(p.string("weight") ?? "medium")
            monospaced = p.bool("monospaced") ?? false
            monospacedDigit = true
        } else {
            text = p.string("text") ?? ""
            weight = parseWeight(p.string("weight"))
            monospacedDigit = p.bool("monospacedDigit") ?? false
        }
    }
}
