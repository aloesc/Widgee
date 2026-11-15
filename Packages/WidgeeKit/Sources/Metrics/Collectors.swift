import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - Сеть

public struct NetworkCounters: Sendable, Equatable {
    public var rxBytes: UInt64
    public var txBytes: UInt64
    public var timestamp: TimeInterval
    public init(rxBytes: UInt64, txBytes: UInt64, timestamp: TimeInterval) {
        self.rxBytes = rxBytes; self.txBytes = txBytes; self.timestamp = timestamp
    }
}

/// Источник счётчиков сети; подменяется в тестах.
public protocol NetworkCounterSource: Sendable {
    func readCounters() -> NetworkCounters
}

/// Реальный источник: сумма по не-loopback интерфейсам через getifaddrs.
public struct SystemNetworkCounterSource: NetworkCounterSource {
    public init() {}
    public func readCounters() -> NetworkCounters {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            var cur: UnsafeMutablePointer<ifaddrs>? = first
            while let p = cur {
                let ifa = p.pointee
                if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                   (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                   (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                   let data = ifa.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx &+= UInt64(d.ifi_ibytes)   // 32-битные счётчики могут переполняться; дельта это учитывает
                    tx &+= UInt64(d.ifi_obytes)
                }
                cur = ifa.ifa_next
            }
            freeifaddrs(first)
        }
        return NetworkCounters(rxBytes: rx, txBytes: tx,
                               timestamp: ProcessInfo.processInfo.systemUptime)
    }
}

/// Считает скорость как дельту между вызовами. Первый вызов даёт 0.
public struct NetworkSampler: Sendable {
    private var previous: NetworkCounters?
    public init() {}

    public mutating func sample(_ now: NetworkCounters) -> NetworkMetrics {
        defer { previous = now }
        guard let prev = previous else { return NetworkMetrics(downBytesPerSec: 0, upBytesPerSec: 0) }
        let dt = now.timestamp - prev.timestamp
        guard dt > 0 else { return NetworkMetrics(downBytesPerSec: 0, upBytesPerSec: 0) }
        // Сброс счётчика (интерфейс пропал) -> 0, а не отрицательное значение.
        let dRx = now.rxBytes >= prev.rxBytes ? now.rxBytes - prev.rxBytes : 0
        let dTx = now.txBytes >= prev.txBytes ? now.txBytes - prev.txBytes : 0
        return NetworkMetrics(downBytesPerSec: Double(dRx) / dt, upBytesPerSec: Double(dTx) / dt)
    }
}

// MARK: - CPU

struct CPUSampler {
    private var previous: [[UInt32]]?   // [core][user, system, idle, nice]

    private static func read() -> [[UInt32]]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { i in
            let b = i * stride
            return [UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                    UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                    UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                    UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])]
        }
    }

    var isPrimed: Bool { previous != nil }

    /// Запоминает базовый замер, чтобы следующий `sample()` дал дельту за короткий интервал.
    mutating func prime() { if previous == nil { previous = Self.read() } }

    /// Без базового замера считает среднее с момента загрузки (поэтому провайдер сначала вызывает `prime()`).
    mutating func sample() -> CPUMetrics {
        guard let cur = Self.read() else {
            return CPUMetrics(total: 0, perCore: [], userRatio: 0, systemRatio: 0)
        }
        defer { previous = cur }
        let prev = previous
        var perCore: [Double] = []
        var u = 0.0, s = 0.0, all = 0.0
        for (i, c) in cur.enumerated() {
            let p: [UInt32] = (prev != nil && prev!.count == cur.count) ? prev![i] : [0, 0, 0, 0]
            let d = (0..<4).map { Double(c[$0] &- p[$0]) }  // wrapping
            let t = d.reduce(0, +)
            perCore.append(t > 0 ? min(1, max(0, (d[0] + d[1] + d[3]) / t)) : 0)
            u += d[0] + d[3]; s += d[1]; all += t
        }
        guard all > 0 else { return CPUMetrics(total: 0, perCore: perCore, userRatio: 0, systemRatio: 0) }
        let ur = min(1, u / all), sr = min(1, s / all)
        return CPUMetrics(total: min(1, ur + sr), perCore: perCore, userRatio: ur, systemRatio: sr)
    }
}

// MARK: - RAM / диск

enum SystemReaders {
    static func sysctlValue<T>(_ name: String, as: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { buf.deallocate() }
        guard sysctlbyname(name, buf, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return buf.load(as: T.self)
    }

    static func ram() -> RAMMetrics {
        let total = sysctlValue("hw.memsize", as: UInt64.self) ?? 0
        let page = UInt64(sysctlValue("hw.pagesize", as: Int32.self) ?? 16384)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var used: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, free: UInt64 = 0
        if kr == KERN_SUCCESS {
            wired = UInt64(stats.wire_count) * page
            compressed = UInt64(stats.compressor_page_count) * page
            let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
            used = min(total, (app &* page) &+ wired &+ compressed)
            free = min(total &- used, UInt64(stats.free_count) * page)
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0, swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = swap.xsu_used; swapTotal = swap.xsu_total
        }
        return RAMMetrics(total: total, used: used, wired: min(wired, total), compressed: min(compressed, total),
                          free: free, swapUsed: swapUsed, swapTotal: swapTotal)
    }

    static func disk() -> DiskMetrics {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return DiskMetrics(total: 0, free: 0) }
        let bs = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * bs
        return DiskMetrics(total: total, free: min(total, UInt64(fs.f_bavail) * bs))
    }

    /// nil, если батареи нет (десктоп).
    static func battery() -> BatteryMetrics? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d["Type"] as? String) == "InternalBattery",
                  let cur = d["Current Capacity"] as? Double ?? (d["Current Capacity"] as? Int).map(Double.init),
                  let mx = d["Max Capacity"] as? Double ?? (d["Max Capacity"] as? Int).map(Double.init),
                  mx > 0 else { continue }
            let plugged = (d["Power Source State"] as? String) == "AC Power"
            let charging = (d["Is Charging"] as? Bool) ?? false
            return BatteryMetrics(level: min(1, max(0, cur / mx)), isCharging: charging, isPluggedIn: plugged)
        }
        return nil
    }

    /// Experimental: утилизация GPU из IOAccelerator PerformanceStatistics (0...1), nil если нет.
    static func gpu() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            guard let prop = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            if let v = (prop["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, min(1, max(0, v / 100)))
            }
        }
        return best
    }

    /// Experimental: на Apple Silicon температура доступна лишь через приватные IOHIDEventSystemClient/SMC,
    /// надёжного публичного пути нет -> всегда nil.
    static func temperature() -> Double? { nil }

    /// Experimental: вентиляторы читаются только через AppleSMC (приватный контракт) -> nil.
    static func fans() -> [Double]? { nil }
}

// MARK: - Процессы

struct ProcessSampler {
    private var previousCPUTime: [Int32: UInt64] = [:]   // ns
    private var previousTime: TimeInterval?
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(1, tb.denom)))
    }()

    mutating func top(by sort: ProcessSort, limit: Int) -> [ProcessInfoEntry] {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = previousTime.map { now - $0 } ?? 0
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 32)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard got > 0 else { return [] }

        var entries: [ProcessInfoEntry] = []
        var times: [Int32: UInt64] = [:]
        for pid in pids.prefix(Int(got)) where pid > 0 {
            var ti = proc_taskinfo()
            let sz = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size))
            guard sz == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }  // нет доступа без root
            let ns = (ti.pti_total_user &+ ti.pti_total_system) &* Self.timebase.numer / Self.timebase.denom
            times[pid] = ns
            var cpu = 0.0
            if dt > 0, let p = previousCPUTime[pid], ns >= p {
                cpu = Double(ns - p) / (dt * 1e9) * 100
            }
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(decoding: nameBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            entries.append(ProcessInfoEntry(pid: pid, name: name.isEmpty ? "pid \(pid)" : name,
                                            cpu: cpu, memoryBytes: ti.pti_resident_size))
        }
        previousCPUTime = times
        previousTime = now
        switch sort {
        case .cpu: entries.sort { ($0.cpu, $0.memoryBytes) > ($1.cpu, $1.memoryBytes) }
        case .memory: entries.sort { $0.memoryBytes > $1.memoryBytes }
        }
        return Array(entries.prefix(max(0, limit)))
    }
}
