import SwiftUI
import Charts
import WidgeeCore

struct PlaceholderView: View {
    var label: String
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .overlay(Text("?").font(.caption2).foregroundStyle(.secondary))
            .frame(minWidth: 16, minHeight: 16)
            .accessibilityLabel(Text(label))
    }
}

struct LinearBarView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let h = p.length("height") ?? 8 * ctx.scale
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let track = ctx.color(p.string("trackColor"), fallback: Color.secondary.opacity(0.25))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(h, g.size.width * p.unit()))
                    .opacity(p.unit() == 0 ? 0 : 1)
            }
        }
        .frame(height: h)
    }
}

struct RingView<Content: View>: View {
    let p: Props; let ctx: RenderContext; let content: Content
    var body: some View {
        let size = p.length("size") ?? 56 * ctx.scale
        let lw = p.length("lineWidth") ?? max(3, size / 8)
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let track = ctx.color(p.string("trackColor"), fallback: Color.secondary.opacity(0.25))
        ZStack {
            Circle().stroke(track, lineWidth: lw)
            Circle().trim(from: 0, to: p.unit())
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .padding(lw / 2)
        .frame(width: size, height: size)
    }
}

struct GaugeView<Content: View>: View {
    let p: Props; let ctx: RenderContext; let content: Content
    var body: some View {
        let size = p.length("size") ?? 80 * ctx.scale
        let lw = p.length("lineWidth") ?? max(4, size / 9)
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let track = ctx.color(p.string("trackColor"), fallback: Color.secondary.opacity(0.25))
        ZStack(alignment: .bottom) {
            SemicircleArc(progress: 1).stroke(track, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            SemicircleArc(progress: p.unit()).stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            content.padding(.bottom, 2)
        }
        .padding(.horizontal, lw / 2)
        .padding(.top, lw / 2)
        .frame(width: size, height: size / 2 + lw / 2)
    }
}

struct SegmentedBarView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let n = p.int("segments", in: 1...100) ?? 10
        let h = p.length("height") ?? 8 * ctx.scale
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let track = ctx.color(p.string("trackColor"), fallback: Color.secondary.opacity(0.25))
        let filled = p.unit() * Double(n)
        HStack(spacing: p.length("spacing") ?? 2) {
            ForEach(0..<n, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(Double(i) + 0.5 <= filled ? color : track)
            }
        }
        .frame(height: h)
    }
}

struct SparklineView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let v = p.numbers("values")
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let h = p.length("height") ?? 28 * ctx.scale
        Chart {
            ForEach(Array(v.enumerated()), id: \.offset) { i, y in
                LineMark(x: .value("i", i), y: .value("v", y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                if p.bool("fill") ?? false {
                    AreaMark(x: .value("i", i), y: .value("v", y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color.opacity(0.2))
                }
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        .frame(height: h)
    }
}

struct LineChartView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let v = p.numbers("values")
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let axes = p.bool("showAxes") ?? true
        let area = p.bool("area") ?? false
        Chart {
            ForEach(Array(v.enumerated()), id: \.offset) { i, y in
                LineMark(x: .value("i", i), y: .value("v", y))
                    .interpolationMethod(.monotone).foregroundStyle(color)
                if area {
                    AreaMark(x: .value("i", i), y: .value("v", y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .chartXAxis(axes ? .automatic : .hidden)
        .chartYAxis(axes ? .automatic : .hidden)
        .chartLegend(.hidden)
        .frame(height: p.length("height") ?? 80 * ctx.scale)
    }
}

struct BarChartView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let v = p.numbers("values")
        let labels = p.strings("labels")
        let color = ctx.color(p.string("color"), fallback: ctx.accent)
        let axes = p.bool("showAxes") ?? false
        Chart {
            ForEach(Array(v.enumerated()), id: \.offset) { i, y in
                BarMark(x: .value("x", i < labels.count ? labels[i] : String(i)), y: .value("v", y))
                    .foregroundStyle(color)
                    .cornerRadius(3)
            }
        }
        .chartXAxis(axes || !labels.isEmpty ? .automatic : .hidden)
        .chartYAxis(axes ? .automatic : .hidden)
        .chartLegend(.hidden)
        .frame(height: p.length("height") ?? 80 * ctx.scale)
    }
}

struct DigitalClockView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let tz = resolveTimeZone(p.string("timeZone"))
        let h12 = p.bool("hour12") ?? false
        let secs = p.bool("showSeconds") ?? false
        let size = p.length("size") ?? 32 * ctx.scale
        let color = ctx.color(p.string("color"))
        let weight = parseWeight(p.string("weight") ?? "medium")
        let part = p.string("part") ?? "all"
        let mono = p.bool("monospaced") ?? false
        let box = ctx.fitBox(p)
        let eff = box.map { $0.height / 1.2 } ?? size
        let m = ctx.textMultiplier
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let t = Text(DigitalClockView.format(tl.date, timeZone: tz, hour12: h12, seconds: secs, part: part))
                .font(mono ? .system(size: eff * m, weight: ctx.weightOverride ?? weight, design: .monospaced) : ctx.font(size: eff, weight: weight))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(color)
            if let box {
                t.minimumScaleFactor(0.02)
                    .frame(width: box.width, height: box.height, alignment: fitAlignment(p.string("align"), default: .center))
            } else {
                t.minimumScaleFactor(0.3)  // широкий шрифт сжимается до ширины блока, а не обрезается «…»
            }
        }
    }

    nonisolated static func format(_ date: Date, timeZone: TimeZone, hour12: Bool, seconds: Bool, part: String = "all") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        if part == "hour" { f.dateFormat = hour12 ? "h" : "HH"; return f.string(from: date) }
        if part == "minute" { f.dateFormat = "mm"; return f.string(from: date) }
        let core = hour12 ? "h:mm" : "HH:mm"
        f.dateFormat = (seconds ? core + ":ss" : core) + (hour12 ? " a" : "")
        return f.string(from: date)
    }
}

struct AnalogClockView: View {
    let p: Props; let ctx: RenderContext
    var body: some View {
        let tz = resolveTimeZone(p.string("timeZone"))
        let h12 = p.bool("hour12") ?? true
        let secs = p.bool("showSeconds") ?? true
        let size = p.length("size") ?? 100 * ctx.scale
        let color = ctx.color(p.string("color"))
        let secColor = ctx.color(p.string("secondColor"), fallback: .orange)
        let numbers = ["all", "quarters", "none"].contains(p.string("numbers") ?? "") ? p.string("numbers")! : "all"
        let ticks = p.bool("ticks") ?? false
        let dots = p.bool("dots") ?? false
        let numR: CGFloat = ticks ? 0.68 : 0.78
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let a = ClockAngles.at(tl.date, timeZone: tz, hour12: h12)
            let r = size / 2
            ZStack {
                if ticks {
                    ForEach(0..<60, id: \.self) { i in
                        let major: Bool = i % 5 == 0
                        let ang: Double = Double(i) * 6 * .pi / 180
                        let len: CGFloat = size * (major ? 0.07 : 0.03)
                        let rr: CGFloat = r - size * 0.03 - len / 2
                        let tw: CGFloat = max(1, size * (major ? 0.02 : 0.01))
                        let px: CGFloat = r + CGFloat(sin(ang)) * rr
                        let py: CGFloat = r - CGFloat(cos(ang)) * rr
                        Capsule().fill(color.opacity(major ? 1.0 : 0.5))
                            .frame(width: tw, height: len)
                            .rotationEffect(.radians(ang))
                            .position(x: px, y: py)
                    }
                }
                if dots {
                    ForEach(0..<12, id: \.self) { i in
                        let ang: Double = Double(i) * 30 * .pi / 180
                        let main: Bool = i % 3 == 0
                        let d: CGFloat = size * (main ? 0.075 : 0.045)
                        let px: CGFloat = r + CGFloat(sin(ang)) * r * 0.82
                        let py: CGFloat = r - CGFloat(cos(ang)) * r * 0.82
                        Circle().fill(color.opacity(main ? 1.0 : 0.6)).frame(width: d, height: d)
                            .position(x: px, y: py)
                    }
                }
                ForEach(0..<12, id: \.self) { i in
                    // 12ч: 12,1..11; 24ч: 24,2,4..22
                    let n = h12 ? (i == 0 ? 12 : i) : (i == 0 ? 24 : i * 2)
                    let ang = Double(i) * 30 * .pi / 180
                    if numbers == "all" || (numbers == "quarters" && i % 3 == 0) {
                        Text("\(n)")
                            .font(ctx.font(size: size * 0.12, weight: .medium))
                            .foregroundStyle(color)
                            .position(x: r + CGFloat(sin(ang)) * r * numR, y: r - CGFloat(cos(ang)) * r * numR)
                    }
                }
                ClockHand(length: r * 0.5, width: max(2, size * 0.035), angle: a.hour, color: color)
                ClockHand(length: r * 0.72, width: max(1.5, size * 0.025), angle: a.minute, color: color)
                if secs {
                    ClockHand(length: r * 0.78, width: max(1, size * 0.012), angle: a.second,
                              color: secColor, tail: r * 0.15)
                }
                Circle().fill(secs ? secColor : color).frame(width: size * 0.05, height: size * 0.05)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
