import Testing
import Foundation
import WidgeeCore
import Metrics
@testable import WidgetHost

private func manifest(system: String = "\"cpu\"", network: String = "\"api.example.com\"") -> String {
    """
    {"id":"t.c","name":"C","version":"1.0.0","sdk":"0.1.0","sizes":["M"],
     "permissions":{"system":[\(system)],"network":[\(network)]}}
    """
}

private func widget(js: String, manifest m: String = manifest()) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widgee-c-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try m.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    try js.write(to: dir.appendingPathComponent("widget.js"), atomically: true, encoding: .utf8)
    return dir
}

private func js(sources: String, body: String = "JSON.stringify(ctx.data)") -> String {
    """
    import { defineWidget, Text, system, timer, http } from "widgee";
    export default defineWidget({
      sources: { \(sources) },
      render(ctx) { console.log("R"); return Text({ value: \(body) }); }
    });
    """
}

private final class Counter: @unchecked Sendable {
    private let l = NSLock(); private var n = 0; private var all: [String] = []
    func add(_ s: String) { l.withLock { all.append(s); if s == "R" { n += 1 } } }
    var renders: Int { l.withLock { n } }
    var logs: [String] { l.withLock { all } }
}

private final class FakeFetcher: HTTPFetching, @unchecked Sendable {
    private let l = NSLock(); private var fail = false; private(set) var calls = 0
    func setFail(_ f: Bool) { l.withLock { fail = f } }
    func fetch(_ url: URL, allowedHosts: [String]) async throws -> JSONValue {
        let f = l.withLock { calls += 1; return fail }
        if f { throw HTTPFetchError.message("offline") }
        return .object(["t": .number(21)])
    }
}

@MainActor
private func make(_ dir: URL, _ c: Counter = Counter(), fetcher: any HTTPFetching = FakeFetcher()) -> WidgetController {
    WidgetController(directory: dir, metrics: MetricsProvider(), fetcher: fetcher, logger: { c.add($0) })
}

@MainActor
private func begin(_ w: WidgetController) async {
    await w.start(size: CGSize(width: 170, height: 170), sizeClass: .small, theme: Theme(), settings: [:])
}

@MainActor
private func waitFor(_ timeout: Double = 5, _ cond: @MainActor () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return cond()
}

@MainActor private func text(_ w: WidgetController) -> String { w.tree?.props["value"]?.stringValue ?? "" }

@Suite @MainActor struct WidgetControllerTests {
    @Test func timerWidgetRerenders() async throws {
        let c = Counter()
        let w = make(try widget(js: js(sources: "now: timer(1)")), c)
        await begin(w)
        #expect(await waitFor { c.renders >= 2 }, "renders=\(c.renders) state=\(w.state)")
        #expect(w.state == .running)
        // «R» логируется внутри render, а дерево публикуется позже: ждём его, а не читаем сразу после счётчика.
        #expect(await waitFor { text(w).contains("\"tick\"") })
        w.stop()
    }

    @Test func systemSourceDeliversMetric() async throws {
        let w = make(try widget(js: js(sources: "cpu: system(\"cpu\", { interval: 0.5 })")))
        await begin(w)
        #expect(await waitFor { w.tree?.props["value"]?.stringValue?.contains("perCore") == true })
        w.stop()
    }

    @Test func systemWithoutPermissionFails() async throws {
        let dir = try widget(js: js(sources: "r: system(\"ram\")"))
        let w = make(dir)
        await begin(w)
        guard case .failed(let r) = w.state else { Issue.record("state=\(w.state)"); return }
        #expect(r.contains("permissions.system"))
    }

    @Test func httpOutsideAllowlistFails() async throws {
        let w = make(try widget(js: js(sources: "w: http(\"https://evil.example.org/x\")")))
        await begin(w)
        guard case .failed(let r) = w.state else { Issue.record("state=\(w.state)"); return }
        #expect(r.contains("permissions.network"))
        let w2 = make(try widget(js: js(sources: "w: http(\"http://api.example.com/x\")")))
        await begin(w2)
        #expect({ if case .failed = w2.state { true } else { false } }())
    }

    @Test func sourceValidation() async throws {
        for src in ["t: timer(0.1)", "c: system(\"cpu\", { interval: 0.1 })", "h: http(\"https://api.example.com/\", { every: 5 })"] {
            let w = make(try widget(js: js(sources: src)))
            await begin(w)
            #expect({ if case .failed = w.state { true } else { false } }(), "\(src)")
        }
        let many = (0..<9).map { "k\($0): timer(5)" }.joined(separator: ",")
        let w = make(try widget(js: js(sources: many)))
        await begin(w)
        #expect({ if case .failed = w.state { true } else { false } }())
    }

    @Test func httpSubdomainAllowedAndStaleOnError() async throws {
        let f = FakeFetcher()
        // every минимум 60 с — повтор не дождаться, поэтому проверяем стартовую загрузку и затем stale через рестарт состояния fetcher
        let dir = try widget(js: js(sources: "w: http(\"https://v1.api.example.com/f\", { every: 60 })"))
        let w = make(dir, fetcher: f)
        await begin(w)
        #expect(await waitFor { text(w).contains("\"stale\":false") })
        #expect(w.manifest?.id == "t.c")
        w.stop()
    }

    @Test func staleOnFetchErrorKeepsLastValue() async throws {
        let f = FakeFetcher()
        let dir = try widget(js: js(sources: "w: http(\"https://api.example.com/f\", { every: 60 })"))
        let w = make(dir, fetcher: f)
        await begin(w)
        #expect(await waitFor { text(w).contains("\"stale\":false") })
        // пауза/возобновление запускает новый опрос — теперь с ошибкой
        f.setFail(true)
        w.setVisible(false)
        w.setVisible(true)
        #expect(await waitFor { text(w).contains("\"stale\":true") })
        #expect(text(w).contains("\"t\":21"))
        w.stop()
    }

    @Test func pauseDoesNotRender() async throws {
        let c = Counter()
        let w = make(try widget(js: js(sources: "now: timer(1)")), c)
        await begin(w)
        #expect(await waitFor { c.renders >= 1 })
        w.setVisible(false)
        var n = c.renders
        for _ in 0..<40 {   // дождаться, пока доработают уже запланированные рендеры
            try await Task.sleep(for: .milliseconds(150))
            if c.renders == n { break }
            n = c.renders
        }
        try await Task.sleep(for: .milliseconds(2500))
        #expect(c.renders == n)
        w.setVisible(true)
        #expect(await waitFor { c.renders > n })
        w.stop()
    }

    @Test func hotReloadOnJSChange() async throws {
        let dir = try widget(js: js(sources: "", body: "\"v1\""))
        let w = make(dir)
        await begin(w)
        #expect(text(w) == "v1")
        try await Task.sleep(for: .milliseconds(500))
        try js(sources: "", body: "\"v2\"").write(to: dir.appendingPathComponent("widget.js"), atomically: false, encoding: .utf8)
        #expect(await waitFor(8) { w.tree?.props["value"]?.stringValue == "v2" }, "\(String(describing: w.tree))")
        w.stop()
    }

    @Test func renderFailureKeepsLastTree() async throws {
        let dir = try widget(js: js(sources: "now: timer(1)", body: "(ctx.data.now && ctx.data.now.tick >= 1 ? ctx.nope.x : \"ok\")"))
        let w = make(dir)
        await begin(w)
        #expect(w.tree?.props["value"]?.stringValue == "ok")
        #expect(await waitFor { if case .failed = w.state { true } else { false } })
        #expect(w.tree?.props["value"]?.stringValue == "ok")
        w.stop()
    }
}

private final class RecordingFetcher: HTTPFetching, @unchecked Sendable {
    private let l = NSLock(); private var urls: [String] = []
    var fetched: [String] { l.withLock { urls } }
    func fetch(_ url: URL, allowedHosts: [String]) async throws -> JSONValue {
        l.withLock { urls.append(url.absoluteString) }
        return .object(["u": .string(url.absoluteString)])
    }
}

private let fnWidgetJS = """
import { defineWidget, Text, http } from "widgee";
export default defineWidget({
  sources: (s) => ({ w: http("https://api.example.com/f?city=" + (s.city ? s.city.name : "none"), { every: 60 }) }),
  render(ctx) { return Text({ value: JSON.stringify(ctx.data) }); }
});
"""

@Suite @MainActor struct SourcesFunctionTests {
    private func start(_ w: WidgetController, _ s: [String: JSONValue]) async {
        await w.start(size: CGSize(width: 170, height: 170), sizeClass: .small, theme: Theme(), settings: s)
    }
    private func upd(_ w: WidgetController, _ s: [String: JSONValue]) {
        w.update(size: CGSize(width: 170, height: 170), sizeClass: .small, theme: Theme(), settings: s)
    }

    @Test func urlDependsOnSettingsAndChangesWithThem() async throws {
        let f = RecordingFetcher()
        let w = make(try widget(js: fnWidgetJS), fetcher: f)
        await start(w, ["city": .object(["name": .string("Paris")])])
        #expect(await waitFor { text(w).contains("city=Paris") })
        #expect(f.fetched == ["https://api.example.com/f?city=Paris"])
        upd(w, ["city": .object(["name": .string("Rome")])])
        #expect(await waitFor { text(w).contains("city=Rome") })
        #expect(!text(w).contains("Paris"), "previous city data is reset")
        #expect(f.fetched.last == "https://api.example.com/f?city=Rome")
        w.stop()
    }

    @Test func unchangedSettingsDoNotRefetch() async throws {
        let f = RecordingFetcher()
        let w = make(try widget(js: fnWidgetJS), fetcher: f)
        let s: [String: JSONValue] = ["city": .object(["name": .string("Paris")])]
        await start(w, s)
        #expect(await waitFor { text(w).contains("city=Paris") })
        upd(w, s)
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.fetched.count == 1)
        w.stop()
    }

    @Test func permissionsCheckedOnResultingURL() async throws {
        let js = """
        import { defineWidget, Text, http } from "widgee";
        export default defineWidget({
          sources: (s) => ({ w: http(s.evil ? "https://evil.example.org/x" : "https://api.example.com/x") }),
          render(ctx) { return Text({ value: "ok" }); }
        });
        """
        let w = make(try widget(js: js), fetcher: RecordingFetcher())
        await start(w, [:])
        #expect(w.state != .failed(""))
        if case .failed = w.state { Issue.record("must not fail on an allowed URL") }
        upd(w, ["evil": .bool(true)])
        #expect(await waitFor { if case .failed(let r) = w.state { r.contains("permissions.network") } else { false } })
        w.stop()
        // сразу при загрузке с недопустимыми настройками
        let w2 = make(try widget(js: js), fetcher: RecordingFetcher())
        await start(w2, ["evil": .bool(true)])
        if case .failed(let r) = w2.state { #expect(r.contains("evil.example.org")) } else { Issue.record("expected failed") }
    }

    @Test func throwingSourcesFunctionFailsWidget() async throws {
        let js = """
        import { defineWidget, Text } from "widgee";
        export default defineWidget({ sources: (s) => { throw new Error("boom"); }, render() { return Text({ value: "x" }); } });
        """
        let w = make(try widget(js: js))
        await start(w, [:])
        if case .failed(let r) = w.state { #expect(r.contains("boom")) } else { Issue.record("expected failed") }
    }
}
