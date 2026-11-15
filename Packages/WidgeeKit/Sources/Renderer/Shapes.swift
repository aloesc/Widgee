import SwiftUI

/// Дуга-полукруг (от 180° до 360°) для Gauge.
struct SemicircleArc: Shape {
    var progress: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        p.addArc(center: center, radius: r, startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * Props.clamp01(progress)), clockwise: false)
        return p
    }
}

/// Углы стрелок в градусах от 12 часов по часовой стрелке.
struct ClockAngles: Equatable {
    var hour: Double
    var minute: Double
    var second: Double

    static func at(_ date: Date, timeZone: TimeZone, hour12: Bool) -> ClockAngles {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let s = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        let m = Double(c.minute ?? 0) + s / 60
        let h = Double(c.hour ?? 0) + m / 60
        let hourAngle = hour12 ? (h.truncatingRemainder(dividingBy: 12)) * 30 : h * 15
        return ClockAngles(hour: hourAngle, minute: m * 6, second: s * 6)
    }
}

func resolveTimeZone(_ id: String?) -> TimeZone {
    guard let id, !id.isEmpty else { return .current }
    return TimeZone(identifier: id) ?? TimeZone(abbreviation: id) ?? .current
}

struct ClockHand: View {
    var length: CGFloat
    var width: CGFloat
    var angle: Double
    var color: Color
    var tail: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length + tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -(length - tail) / 2)
            .rotationEffect(.degrees(angle))
    }
}
