import Testing
import Foundation
@testable import Metrics

@Test func ringBufferOverflowKeepsOrder() {
    var rb = RingBuffer<Int>(capacity: 3)
    #expect(rb.elements.isEmpty && rb.last == nil)
    for i in 1...2 { rb.append(i) }
    #expect(rb.elements == [1, 2] && rb.last == 2)
    for i in 3...7 { rb.append(i) }
    #expect(rb.elements == [5, 6, 7])
    #expect(rb.count == 3 && rb.last == 7)
}

@Test func historyPerKind() {
    var h = MetricHistory(capacity: 2)
    h.record(.gpu(0.1), for: .gpu); h.record(.gpu(0.2), for: .gpu); h.record(.gpu(0.3), for: .gpu)
    h.record(.temperature(nil), for: .temperature)
    #expect(h.values(for: .gpu) == [.gpu(0.2), .gpu(0.3)])
    #expect(h.values(for: .temperature).count == 1)
    #expect(h.values(for: .cpu).isEmpty)
}

@Test func networkDelta() {
    var s = NetworkSampler()
    let a = s.sample(NetworkCounters(rxBytes: 1000, txBytes: 500, timestamp: 10))
    #expect(a == NetworkMetrics(downBytesPerSec: 0, upBytesPerSec: 0))
    let b = s.sample(NetworkCounters(rxBytes: 3000, txBytes: 1500, timestamp: 12))
    #expect(b == NetworkMetrics(downBytesPerSec: 1000, upBytesPerSec: 500))
    let c = s.sample(NetworkCounters(rxBytes: 10, txBytes: 10, timestamp: 13)) // сброс счётчика
    #expect(c.downBytesPerSec == 0 && c.upBytesPerSec == 0)
}

private final class FakeSource: NetworkCounterSource, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NetworkCounters]
    init(_ items: [NetworkCounters]) { self.items = items }
    func readCounters() -> NetworkCounters { lock.withLock { items.removeFirst() } }
}

@Test func providerUsesInjectedSource() async {
    let src = FakeSource([.init(rxBytes: 0, txBytes: 0, timestamp: 0), .init(rxBytes: 400, txBytes: 200, timestamp: 2)])
    let p = MetricsProvider(networkSource: src)
    _ = await p.snapshot(.network)
    guard case .network(let n) = await p.snapshot(.network) else { Issue.record("wrong kind"); return }
    #expect(n.downBytesPerSec == 200 && n.upBytesPerSec == 100)
    #expect(await p.history(for: .network).count == 2)
}

@Test func realCPUBounds() async {
    let p = MetricsProvider()
    _ = await p.snapshot(.cpu)
    try? await Task.sleep(for: .milliseconds(100))
    guard case .cpu(let c) = await p.snapshot(.cpu) else { Issue.record("wrong kind"); return }
    #expect((0...1).contains(c.total))
    #expect(!c.perCore.isEmpty && c.perCore.allSatisfy { (0...1).contains($0) })
    #expect((0...1).contains(c.userRatio) && (0...1).contains(c.systemRatio))
}

@Test func firstCPUSnapshotIsPrimedDelta() async {
    var sampler = CPUSampler()
    #expect(!sampler.isPrimed)
    sampler.prime()
    #expect(sampler.isPrimed)

    let p = MetricsProvider()
    let t0 = Date()
    guard case .cpu(let c) = await p.snapshot(.cpu) else { Issue.record("wrong kind"); return }
    // The provider primes a baseline and waits: the first result is a delta, not an instant 0.
    #expect(Date().timeIntervalSince(t0) >= 0.1)
    #expect(!c.perCore.isEmpty && (0...1).contains(c.total))
}

@Test func realRAMAndDisk() async {
    let p = MetricsProvider()
    guard case .ram(let r) = await p.snapshot(.ram) else { Issue.record("wrong kind"); return }
    #expect(r.total > 0 && r.used <= r.total && r.free <= r.total)
    #expect(r.wired <= r.total && r.compressed <= r.total && r.swapUsed <= r.swapTotal)
    guard case .disk(let d) = await p.snapshot(.disk) else { Issue.record("wrong kind"); return }
    #expect(d.total > 0 && d.free <= d.total)
}

@Test func realNetworkFirstCallIsZero() async {
    let p = MetricsProvider()
    guard case .network(let n) = await p.snapshot(.network) else { Issue.record("wrong kind"); return }
    #expect(n.downBytesPerSec == 0 && n.upBytesPerSec == 0)
}

@Test func optionalMetricsMayBeNil() async {
    let p = MetricsProvider()
    if case .battery(let b?) = await p.snapshot(.battery) { #expect((0...1).contains(b.level)) }
    if case .gpu(let g?) = await p.snapshot(.gpu) { #expect((0...1).contains(g)) }
    _ = await p.snapshot(.temperature)
    _ = await p.snapshot(.fans)
}

@Test func processes() async {
    let p = MetricsProvider()
    let list = await p.topProcesses(by: .memory, limit: 5)
    #expect(list.count <= 5)
    #expect(list.map(\.memoryBytes) == list.map(\.memoryBytes).sorted(by: >))
    #expect(list.allSatisfy { $0.pid > 0 && $0.cpu >= 0 })
}
