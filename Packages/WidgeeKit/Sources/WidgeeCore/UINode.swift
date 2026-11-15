import Foundation

/// Узел декларативного дерева, которое возвращает `render(ctx)` из JS.
/// `type` — имя компонента: VStack, HStack, ZStack, Spacer, Text, Image,
/// LinearBar, Ring, Gauge, SegmentedBar, Sparkline, LineChart, BarChart,
/// DigitalClock, AnalogClock.
public struct UINode: Codable, Equatable, Sendable {
    public var type: String
    public var props: [String: JSONValue]
    public var children: [UINode]

    public init(type: String, props: [String: JSONValue] = [:], children: [UINode] = []) {
        self.type = type
        self.props = props
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case type, props, children }

    /// `props` и `children` необязательны в JSON, JS-фабрики могут их опускать.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        props = try c.decodeIfPresent([String: JSONValue].self, forKey: .props) ?? [:]
        children = try c.decodeIfPresent([UINode].self, forKey: .children) ?? []
    }
}
