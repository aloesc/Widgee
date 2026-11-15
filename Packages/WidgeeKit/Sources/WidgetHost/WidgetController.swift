import Foundation
import AppKit
import Combine
import WidgeeCore
import Metrics

/// Владеет WidgetRuntime одного виджета: опросы источников, перерисовка, пауза, hot reload.
@MainActor
public final class WidgetController: ObservableObject {
    @Published public private(set) var tree: UINode?
    @Published public private(set) var state: WidgetState = .loaded
    public private(set) var manifest: WidgetManifest?

    private let directory: URL
    private let hostSDK: SemVer?
    private let metrics: MetricsProvider
    private let fetcher: any HTTPFetching
    private let logger: @Sendable (String) -> Void

    private var runtime: WidgetRuntime?
    private var size = CGSize(width: 170, height: 170)
    private var sizeClass = SizeClass.small
    private var theme = Theme()
    private var settings: [String: JSONValue] = [:]

    private var data: [String: JSONValue] = [:]
    private var activeSpecs: [SourceSpec] = []
    private var sourcesEpoch = 0
    private var pollers: [Task<Void, Never>] = []
    private var debounce: Task<Void, Never>?
    private var rendering = false
    private var dirty = false

    private var started = false
    private var visible = true
    private var sleeping = false
    private var watcher: DirectoryWatcher?
    private var reloadTask: Task<Void, Never>?
    private var lastFingerprint: [String] = []
    private let observers = Observers()

    /// `fetcher` добавлен сверх заданного API (значение по умолчанию — реальная сеть) для тестов.
    public init(directory: URL, hostSDK: SemVer? = nil, metrics: MetricsProvider,
                fetcher: any HTTPFetching = URLSessionHTTPFetcher(),
                logger: @escaping @Sendable (String) -> Void) {
        self.directory = directory; self.hostSDK = hostSDK; self.metrics = metrics
        self.fetcher = fetcher; self.logger = logger
    }

    // MARK: API

    public func start(size: CGSize, sizeClass: SizeClass, theme: Theme, settings: [String: JSONValue]) async {
        self.size = size; self.sizeClass = sizeClass; self.theme = theme; self.settings = settings
        started = true
        installObservers()
        installWatcher()
        await load(restart: false)
    }

    public func update(size: CGSize, sizeClass: SizeClass, theme: Theme, settings: [String: JSONValue]) {
        let settingsChanged = self.settings != settings
        self.size = size; self.sizeClass = sizeClass; self.theme = theme; self.settings = settings
        guard runtime != nil, !isFailed else { return }
        if settingsChanged { Task { await refreshSources() } } else { Task { await flushRender() } }
    }

    public func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        applyActivity()
    }

    public func restart() async {
        guard started else { return }
        await load(restart: true)
    }

    public func stop() {
        started = false
        stopPollers()
        debounce?.cancel(); reloadTask?.cancel()
        watcher?.stop(); watcher = nil
        observers.removeAll()
    }

    // MARK: загрузка

    private var isFailed: Bool { if case .failed = state { true } else { false } }
    private var active: Bool { started && visible && !sleeping && runtime != nil && !isFailed }

    /// Отпечаток manifest.json и *.js (путь, mtime, размер): отсекает ложные события FSEvents без правок.
    private func fingerprint() -> [String] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        var out: [String] = []
        for case let u as URL in e where u.lastPathComponent == "manifest.json" || u.pathExtension == "js" {
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            out.append("\(u.path)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(v?.fileSize ?? 0)")
        }
        return out.sorted()
    }

    private func load(restart: Bool) async {
        lastFingerprint = fingerprint()
        stopPollers()
        debounce?.cancel()
        data = [:]
        sourcesEpoch += 1
        let rt: WidgetRuntime
        if restart, let r = runtime { await r.restart(settings: settings); rt = r }
        else {
            let log = logger
            rt = await WidgetRuntime.load(directory: directory,
                                          hostSDK: hostSDK?.description ?? WidgeeCore.sdkVersion,
                                          settings: settings,
                                          logger: { level, msg in log(level == "log" ? msg : "[\(level)] \(msg)") })
        }
        guard started else { return }
        runtime = rt
        manifest = rt.manifest
        if case .failed(let r) = rt.state { state = .failed(r); return }
        activeSpecs = rt.sources
        for s in activeSpecs { data[s.key] = .null }
        state = .running
        applyActivity()
        await flushRender()
    }

    /// Новые settings: пересчитывает `sources`; если набор изменился, пересоздаёт опросы и сбрасывает данные.
    private func refreshSources() async {
        guard let rt = runtime, !isFailed else { return }
        sourcesEpoch += 1
        let epoch = sourcesEpoch
        let specs: [SourceSpec]
        do { specs = try await rt.resolveSources(settings: settings) }
        catch {
            guard runtime === rt, epoch == sourcesEpoch else { return }
            state = .failed((error as? WidgetError)?.description ?? "\(error)")
            stopPollers()
            return
        }
        guard runtime === rt, started, epoch == sourcesEpoch else { return }
        if specs != activeSpecs {
            stopPollers()
            debounce?.cancel()
            activeSpecs = specs
            data = [:]
            for s in specs { data[s.key] = .null }
            applyActivity()
        }
        await flushRender()
    }

    private func applyActivity() {
        if active {
            if pollers.isEmpty { startPollers() }
        } else {
            stopPollers()
        }
    }

    // MARK: опросы

    private func stopPollers() {
        pollers.forEach { $0.cancel() }
        pollers = []
    }

    private func startPollers() {
        guard let rt = runtime, let m = rt.manifest else { return }
        let allowed = m.permissions.network
        for spec in activeSpecs {
            let task: Task<Void, Never>
            switch spec.kind {
            case .timer(let interval):
                task = Task { [weak self] in
                    var tick = 0
                    while !Task.isCancelled {
                        let now = Date().timeIntervalSince1970 * 1000
                        self?.deliver(spec.key, .object(["now": .number(now.rounded()), "tick": .number(Double(tick))]))
                        tick += 1
                        try? await Task.sleep(for: .seconds(interval))
                    }
                }
            case .system(let metric, let interval):
                let provider = metrics
                task = Task { [weak self] in
                    while !Task.isCancelled {
                        let v = await provider.snapshot(metric).json
                        if Task.isCancelled { break }
                        self?.deliver(spec.key, v)
                        try? await Task.sleep(for: .seconds(interval))
                    }
                }
            case .http(let url, let every):
                let fetcher = self.fetcher, log = logger
                task = Task { [weak self] in
                    while !Task.isCancelled {
                        do {
                            let v = try await fetcher.fetch(url, allowedHosts: allowed)
                            if Task.isCancelled { break }
                            self?.deliver(spec.key, .object(["value": v, "updatedAt": .number((Date().timeIntervalSince1970 * 1000).rounded()),
                                                              "stale": .bool(false)]))
                        } catch {
                            if Task.isCancelled { break }
                            log("[warn] http \(url.host ?? ""): \(error)")
                            self?.markStale(spec.key)
                        }
                        try? await Task.sleep(for: .seconds(every))
                    }
                }
            }
            pollers.append(task)
        }
    }

    private func deliver(_ key: String, _ value: JSONValue) {
        guard active else { return }
        data[key] = value
        scheduleRender()
    }

    private func markStale(_ key: String) {
        guard active, case .object(var o)? = data[key] else { return }
        o["stale"] = .bool(true)
        data[key] = .object(o)
        scheduleRender()
    }

    // MARK: render

    private func scheduleRender() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            await self?.flushRender()
        }
    }

    private func flushRender() async {
        guard let rt = runtime, !isFailed else { return }
        if rendering { dirty = true; return }
        rendering = true
        defer { rendering = false }
        repeat {
            dirty = false
            let ctx = RenderContext(size: .init(width: size.width, height: size.height, sizeClass: sizeClass),
                                    theme: theme, settings: settings, data: .object(data))
            do {
                let t = try await rt.render(ctx)
                guard runtime === rt, started else { return }
                tree = t
            } catch {
                guard runtime === rt else { return }
                state = .failed((error as? WidgetError)?.description ?? "\(error)")
                stopPollers()
                return
            }
        } while dirty
    }

    // MARK: сон/пробуждение, hot reload

    private func installObservers() {
        guard observers.tokens.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, sleeping: Bool) {
            let t = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = sleeping
                    self.applyActivity()
                }
            }
            observers.tokens.append(t)
        }
        add(NSWorkspace.screensDidSleepNotification, sleeping: true)
        add(NSWorkspace.willSleepNotification, sleeping: true)
        add(NSWorkspace.screensDidWakeNotification, sleeping: false)
        add(NSWorkspace.didWakeNotification, sleeping: false)
    }

    private func installWatcher() {
        watcher?.stop()
        watcher = DirectoryWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            guard let self, self.fingerprint() != self.lastFingerprint else { return }
            self.logger("hot reload")
            await self.restart()
        }
    }

    private final class Observers: @unchecked Sendable {
        var tokens: [NSObjectProtocol] = []
        func removeAll() {
            tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            tokens = []
        }
        deinit { removeAll() }
    }
}
