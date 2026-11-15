import Foundation

public struct CPUMetrics: Sendable, Equatable {
    /// Общая загрузка 0...1.
    public var total: Double
    public var perCore: [Double]
    public var userRatio: Double
    public var systemRatio: Double
    public init(total: Double, perCore: [Double], userRatio: Double, systemRatio: Double) {
        self.total = total; self.perCore = perCore
        self.userRatio = userRatio; self.systemRatio = systemRatio
    }
}

public struct RAMMetrics: Sendable, Equatable {
    public var total: UInt64
    public var used: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public init(total: UInt64, used: UInt64, wired: UInt64, compressed: UInt64,
                free: UInt64, swapUsed: UInt64, swapTotal: UInt64) {
        self.total = total; self.used = used; self.wired = wired
        self.compressed = compressed; self.free = free
        self.swapUsed = swapUsed; self.swapTotal = swapTotal
    }
}

public struct DiskMetrics: Sendable, Equatable {
    public var total: UInt64
    public var free: UInt64
    public init(total: UInt64, free: UInt64) { self.total = total; self.free = free }
}

public struct NetworkMetrics: Sendable, Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double
    public init(downBytesPerSec: Double, upBytesPerSec: Double) {
        self.downBytesPerSec = downBytesPerSec; self.upBytesPerSec = upBytesPerSec
    }
}

public struct BatteryMetrics: Sendable, Equatable {
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public init(level: Double, isCharging: Bool, isPluggedIn: Bool) {
        self.level = level; self.isCharging = isCharging; self.isPluggedIn = isPluggedIn
    }
}

public struct ProcessInfoEntry: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    /// Загрузка CPU в процентах одного ядра (может быть >100). 0 при первом замере.
    public var cpu: Double
    public var memoryBytes: UInt64
    public init(pid: Int32, name: String, cpu: Double, memoryBytes: UInt64) {
        self.pid = pid; self.name = name; self.cpu = cpu; self.memoryBytes = memoryBytes
    }
}

public enum ProcessSort: Sendable { case cpu, memory }

public enum MetricKind: String, Sendable, CaseIterable, Hashable {
    case cpu, ram, disk, network, battery, processes, temperature, fans, gpu
}

public enum MetricValue: Sendable, Equatable {
    case cpu(CPUMetrics)
    case ram(RAMMetrics)
    case disk(DiskMetrics)
    case network(NetworkMetrics)
    case battery(BatteryMetrics?)
    case processes([ProcessInfoEntry])
    case temperature(Double?)   // experimental
    case fans([Double]?)        // experimental
    case gpu(Double?)           // experimental
}
