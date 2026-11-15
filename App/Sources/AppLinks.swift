import AppKit

/// Внешние ссылки приложения: меняются в одном месте.
enum AppLinks {
    static let donate = URL(string: "https://donatty.com/aloescc")!
    static let repository = URL(string: "https://github.com/aloesc/Widgee")!
    static let issues = URL(string: "https://github.com/aloesc/Widgee/issues")!
    static let license = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// Открывает ссылку в браузере по умолчанию.
    @MainActor
    static func open(_ url: URL) {
        #if DEBUG
        AppState.logger.info("open url: \(url.absoluteString, privacy: .public)")
        if CommandLine.arguments.contains("--no-open-urls") { return }
        #endif
        NSWorkspace.shared.open(url)
    }
}
