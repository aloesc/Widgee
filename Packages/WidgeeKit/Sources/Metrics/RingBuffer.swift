/// Кольцевой буфер фиксированной ёмкости; при переполнении вытесняет самые старые элементы.
public struct RingBuffer<T: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [T] = []
    private var head = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: T) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Элементы от старого к новому.
    public var elements: [T] {
        guard storage.count == capacity, head != 0 else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    public var last: T? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }
}

/// Последние N точек по каждому виду метрики.
public struct MetricHistory: Sendable {
    public let capacity: Int
    private var buffers: [MetricKind: RingBuffer<MetricValue>] = [:]

    public init(capacity: Int = 60) { self.capacity = max(1, capacity) }

    public mutating func record(_ value: MetricValue, for kind: MetricKind) {
        buffers[kind, default: RingBuffer(capacity: capacity)].append(value)
    }

    public func values(for kind: MetricKind) -> [MetricValue] {
        buffers[kind]?.elements ?? []
    }
}
