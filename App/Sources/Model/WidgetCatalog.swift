import Foundation
import WidgeeCore
import WidgetHost
import Background

/// Доступный виджет: встроенный (из бандла) или пользовательский.
struct CatalogEntry: Identifiable, Equatable {
    var id: String { manifest.id }
    let manifest: WidgetManifest
    let directory: URL
    let isBuiltin: Bool
    let description: String
    let category: String
    /// Варианты для `select`-настроек (из `WidgetSettingField.options`).
    let selectOptions: [String: [String]]
    /// Фон нового экземпляра (`defaultBackground` в манифесте: style color|tint, hex, opacity); пользователь может изменить.
    var defaultBackground: WidgetBackgroundStyle? = nil

    var defaultSettings: [String: JSONValue] {
        var r: [String: JSONValue] = [:]
        for f in manifest.settings { if let d = f.default { r[f.key] = d } }
        return r
    }

    var defaultPreset: WidgetSizePreset {
        for s in ["M", "S", "L", "XL"] where manifest.sizes.contains(s) { return WidgetSizePreset(rawValue: s)! }
        return .M
    }
}

@MainActor
final class WidgetCatalog: ObservableObject {
    @Published private(set) var entries: [CatalogEntry] = []
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void) { self.log = log }

    static var builtinDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("BuiltinWidgets", isDirectory: true)
    }

    func entry(_ id: String) -> CatalogEntry? { entries.first { $0.id == id } }

    func reload() {
        var result: [CatalogEntry] = []
        var seen = Set<String>()
        var roots: [(URL, Bool)] = []
        if let b = Self.builtinDirectory { roots.append((b, true)) }
        roots.append((ConfigStore.userWidgetsDirectory, false))
        for (root, builtin) in roots {
            let dirs = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                do {
                    let data = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
                    let m = try WidgetManifest.parse(data)
                    guard seen.insert(m.id).inserted else {
                        log("widget \(m.id) in \(dir.path) skipped: id already in use")
                        continue
                    }
                    let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    var options: [String: [String]] = [:]
                    for f in m.settings { if let o = f.options { options[f.key] = o } }
                    var bg: WidgetBackgroundStyle?
                    if let d = raw["defaultBackground"] as? [String: Any], let hex = d["hex"] as? String {
                        let o = min(1, max(0, (d["opacity"] as? Double) ?? 0.8))
                        switch d["style"] as? String {
                        case "color": bg = .color(hex: hex, opacity: o)
                        case "tint": bg = .tint(hex: hex, opacity: o)
                        default: break
                        }
                    }
                    result.append(CatalogEntry(
                        manifest: m, directory: dir, isBuiltin: builtin,
                        description: raw["description"] as? String ?? "",
                        category: raw["category"] as? String ?? "other",
                        selectOptions: options, defaultBackground: bg))
                } catch {
                    log("widget in \(dir.path) failed to load: \(error)")
                }
            }
        }
        entries = result
    }
}
