import Foundation

public actor MetricsProvider {
    private var cpuSampler = CPUSampler()
    private var networkSampler = NetworkSampler()
    private var processSampler = ProcessSampler()
    private let networkSource: any NetworkCounterSource
    private var history: MetricHistory

    public init(networkSource: any NetworkCounterSource = SystemNetworkCounterSource(),
                historyCapacity: Int = 60) {
        self.networkSource = networkSource
        self.history = MetricHistory(capacity: historyCapacity)
    }

    public func snapshot(_ metric: MetricKind) async -> MetricValue {
        let value: MetricValue
        switch metric {
        case .cpu:
            if !cpuSampler.isPrimed {
                // Базовый замер + короткая пауза: первый результат — дельта за ~150 мс, а не 0 и не среднее с загрузки.
                cpuSampler.prime()
                try? await Task.sleep(for: .milliseconds(150))
            }
            value = .cpu(cpuSampler.sample())
        case .ram: value = .ram(SystemReaders.ram())
        case .disk: value = .disk(SystemReaders.disk())
        case .network: value = .network(networkSampler.sample(networkSource.readCounters()))
        case .battery: value = .battery(SystemReaders.battery())
        case .processes: value = .processes(processSampler.top(by: .cpu, limit: 5))
        case .temperature: value = .temperature(SystemReaders.temperature())
        case .fans: value = .fans(SystemReaders.fans())
        case .gpu: value = .gpu(SystemReaders.gpu())
        }
        history.record(value, for: metric)
        return value
    }

    public func topProcesses(by sort: ProcessSort, limit: Int) async -> [ProcessInfoEntry] {
        processSampler.top(by: sort, limit: limit)
    }

    public func history(for metric: MetricKind) -> [MetricValue] {
        history.values(for: metric)
    }
}
