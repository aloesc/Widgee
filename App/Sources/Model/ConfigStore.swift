import Foundation

/// Хранилище конфигурации: JSON, атомарная запись, резервная копия повреждённого файла.
struct ConfigStore: Sendable {
    let url: URL

    static var supportDirectory: URL {
        #if DEBUG
        // Изолированный конфиг для скриншотов и автотестов: не трогаем данные пользователя.
        if let dir = ProcessInfo.processInfo.environment["WIDGEE_SUPPORT_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Widgee", isDirectory: true)
    }
    static var userWidgetsDirectory: URL {
        supportDirectory.appendingPathComponent("Widgets", isDirectory: true)
    }
    static var `default`: ConfigStore { ConfigStore(url: supportDirectory.appendingPathComponent("config.json")) }

    /// Читает конфиг. Нет файла -> значения по умолчанию. Повреждённый файл переименовывается
    /// в `config.corrupt-<время>.json`, возвращаются значения по умолчанию.
    func load(log: (String) -> Void = { _ in }) -> AppConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return AppConfig() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.corrupt-\(stamp).json")
            do {
                try fm.moveItem(at: url, to: backup)
                log("config.json is corrupted (\(error)); backup: \(backup.lastPathComponent)")
            } catch {
                log("config.json is corrupted and could not be backed up: \(error)")
            }
            return AppConfig()
        }
    }

    func save(_ config: AppConfig) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: url, options: .atomic)
    }
}
