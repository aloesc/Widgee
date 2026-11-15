import Foundation
import WidgeeCore

public protocol HTTPFetching: Sendable {
    /// Загружает JSON. `allowedHosts` — allowlist для проверки редиректов.
    func fetch(_ url: URL, allowedHosts: [String]) async throws -> JSONValue
}

public enum HTTPFetchError: Error, CustomStringConvertible, Sendable {
    case message(String)
    public var description: String { if case .message(let m) = self { m } else { "" } }
}

/// Реальный загрузчик: ephemeral-сессия, без cookies/авторизации, таймаут 15 с, лимит 1 МБ, только JSON.
public struct URLSessionHTTPFetcher: HTTPFetching {
    public static let maxBytes = 1_000_000
    public init() {}

    private final class Redirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let allowed: [String]
        init(_ a: [String]) { allowed = a }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let u = request.url, u.scheme?.lowercased() == "https", let h = u.host,
                  SourceSpec.hostAllowed(h, in: allowed) else { return nil }
            return request
        }
    }

    public func fetch(_ url: URL, allowedHosts: [String]) async throws -> JSONValue {
        guard url.scheme?.lowercased() == "https", let h = url.host, SourceSpec.hostAllowed(h, in: allowedHosts) else {
            throw HTTPFetchError.message("host not allowed")
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 15
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpShouldHandleCookies = false
        let (bytes, resp) = try await session.bytes(for: req, delegate: Redirects(allowedHosts))
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HTTPFetchError.message("HTTP status \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard type.contains("json") else { throw HTTPFetchError.message("response is not JSON (\(type))") }
        if http.expectedContentLength > Int64(Self.maxBytes) { throw HTTPFetchError.message("response is larger than 1 MB") }
        var data = Data()
        for try await b in bytes {
            data.append(b)
            if data.count > Self.maxBytes { throw HTTPFetchError.message("response is larger than 1 MB") }
        }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw HTTPFetchError.message("invalid JSON") }
    }
}
