import Foundation
import WidgeeCore
import Metrics

/// Декларативный источник данных из `defineWidget({ sources })`.
public struct SourceSpec: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case system(metric: MetricKind, interval: Double)
        case timer(interval: Double)
        case http(url: URL, every: Double)
    }
    public var key: String
    public var kind: Kind
    public init(key: String, kind: Kind) { self.key = key; self.kind = kind }

    public static let maxSources = 8
    public static let systemRange: ClosedRange<Double> = 0.5...3600
    public static let timerRange: ClosedRange<Double> = 1...86400
    public static let httpRange: ClosedRange<Double> = 60...86400

    /// Хост разрешён: точное совпадение или поддомен домена из списка.
    public static func hostAllowed(_ host: String, in allowlist: [String]) -> Bool {
        let h = host.lowercased()
        return allowlist.contains { d in
            let d = d.lowercased()
            return h == d || h.hasSuffix("." + d)
        }
    }

    /// Разбор JSON `def.sources` и проверка прав из манифеста.
    static func parse(json: String, permissions: WidgetPermissions) throws -> [SourceSpec] {
        func bad(_ s: String) -> WidgetError { .failed(s) }
        guard let obj = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
              case .object(let dict) = obj else { throw bad("sources must be an object { key: source } or a function (settings) => object") }
        guard dict.count <= maxSources else { throw bad("more than \(maxSources) sources") }
        var out: [SourceSpec] = []
        for key in dict.keys.sorted() {
            guard !key.isEmpty else { throw bad("empty source key") }
            guard case .object(let d) = dict[key]!, let kind = d["kind"]?.stringValue else {
                throw bad("source “\(key)”: expected system(...), timer(...) or http(...)")
            }
            func interval(_ name: String, default def: Double?, _ range: ClosedRange<Double>) throws -> Double {
                var v = def
                if let raw = d[name], raw != .null {
                    guard let n = raw.numberValue, n.isFinite else { throw bad("source “\(key)”: \(name) must be a number") }
                    v = n
                }
                guard let v else { throw bad("source “\(key)”: \(name) is not set") }
                guard range.contains(v) else {
                    throw bad("source “\(key)”: \(name)=\(v) is outside the range \(range.lowerBound)...\(range.upperBound) s")
                }
                return v
            }
            switch kind {
            case "system":
                guard let name = d["metric"]?.stringValue, let metric = MetricKind(rawValue: name) else {
                    throw bad("source “\(key)”: unknown metric")
                }
                guard permissions.system.contains(name) else {
                    throw bad("source “\(key)”: permissions.system “\(name)” is missing in manifest.json")
                }
                out.append(.init(key: key, kind: .system(metric: metric, interval: try interval("interval", default: 2, systemRange))))
            case "timer":
                out.append(.init(key: key, kind: .timer(interval: try interval("seconds", default: nil, timerRange))))
            case "http":
                guard let s = d["url"]?.stringValue, let url = URL(string: s),
                      let host = url.host, !host.isEmpty else { throw bad("source “\(key)”: invalid url") }
                guard url.scheme?.lowercased() == "https" else { throw bad("source “\(key)”: only https is allowed") }
                guard hostAllowed(host, in: permissions.network) else {
                    throw bad("source “\(key)”: host “\(host)” is not listed in permissions.network")
                }
                out.append(.init(key: key, kind: .http(url: url, every: try interval("every", default: 600, httpRange))))
            default:
                throw bad("source “\(key)”: unknown kind “\(kind)”")
            }
        }
        return out
    }
}

extension MetricValue {
    /// JSON-представление для `ctx.data`.
    var json: JSONValue {
        func n(_ v: UInt64) -> JSONValue { .number(Double(v)) }
        switch self {
        case .cpu(let c):
            return .object(["total": .number(c.total), "perCore": .array(c.perCore.map { .number($0) }),
                            "user": .number(c.userRatio), "system": .number(c.systemRatio)])
        case .ram(let r):
            return .object(["total": n(r.total), "used": n(r.used), "wired": n(r.wired), "compressed": n(r.compressed),
                            "free": n(r.free), "swapUsed": n(r.swapUsed), "swapTotal": n(r.swapTotal)])
        case .disk(let d): return .object(["total": n(d.total), "free": n(d.free)])
        case .network(let w):
            return .object(["downBytesPerSec": .number(w.downBytesPerSec), "upBytesPerSec": .number(w.upBytesPerSec)])
        case .battery(let b):
            guard let b else { return .null }
            return .object(["level": .number(b.level), "isCharging": .bool(b.isCharging), "isPluggedIn": .bool(b.isPluggedIn)])
        case .processes(let p):
            return .array(p.map { .object(["pid": .number(Double($0.pid)), "name": .string($0.name),
                                           "cpu": .number($0.cpu), "memoryBytes": n($0.memoryBytes)]) })
        case .temperature(let v), .gpu(let v): return v.map { .number($0) } ?? .null
        case .fans(let v): return v.map { .array($0.map { .number($0) }) } ?? .null
        }
    }
}
