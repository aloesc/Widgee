import SwiftUI
import CoreLocation
import MapKit
import WidgeeCore
import WidgetHost

/// Поиск города через геокодинг Open-Meteo (запрос выполняет приложение, не JS).
@MainActor
final class CitySearchModel: ObservableObject {
    @Published var results: [CitySetting] = []
    @Published var status: String?
    @Published var isLoading = false
    @Published var isLocating = false

    private var task: Task<Void, Never>?
    private let locator = LocationResolver()

    static func searchURL(query: String, language: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "8"),
                         .init(name: "language", value: language), .init(name: "format", value: "json")]
        return c?.url
    }

    /// Вызывается при каждом изменении текста; запрос уходит после паузы 450 мс.
    func queryChanged(_ raw: String) {
        task?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []; status = nil; isLoading = false
            return
        }
        isLoading = true
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            await self?.search(q)
        }
    }

    private func search(_ q: String) async {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        guard let url = Self.searchURL(query: q, language: lang) else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if Task.isCancelled { return }
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let found = Self.parse(data)
            results = found
            status = found.isEmpty ? "No results" : nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            results = []
            status = Self.describe(error)
        }
        isLoading = false
    }

    nonisolated static func parse(_ data: Data) -> [CitySetting] {
        struct Resp: Decodable {
            struct Item: Decodable { let name: String; let latitude: Double; let longitude: Double
                                     let country: String?; let admin1: String? }
            let results: [Item]?
        }
        let items = (try? JSONDecoder().decode(Resp.self, from: data))?.results ?? []
        return items.compactMap { CitySetting(json: .object([
            "name": .string($0.name), "latitude": .number($0.latitude), "longitude": .number($0.longitude),
            "country": $0.country.map { .string($0) } ?? .null])) }
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut: "The geocoding service timed out"
        case .notConnectedToInternet, .networkConnectionLost: "No network connection"
        case .some: "Network error: \(error.localizedDescription)"
        case nil: "Search failed: \(error.localizedDescription)"
        }
    }

    /// Разрешение запрашивается только здесь, по нажатию кнопки.
    func useCurrentLocation(_ done: @escaping (CitySetting) -> Void) {
        guard !isLocating else { return }
        isLocating = true; status = nil
        Task {
            do {
                done(try await locator.resolveCity())
            } catch {
                status = (error as? LocationError)?.message ?? "Could not determine your location: \(error.localizedDescription)"
            }
            isLocating = false
        }
    }
}

enum LocationError: Error {
    case denied, unavailable
    var message: String {
        switch self {
        case .denied: "Location access is denied. Allow it in System Settings > Privacy & Security > Location Services."
        case .unavailable: "Location services are unavailable or the position could not be determined."
        }
    }
}

/// Одноразовое получение положения через CoreLocation + обратный геокодинг через MapKit.
@MainActor
final class LocationResolver: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation, Error>?
    private var waitingForAuth = false

    override init() { super.init(); manager.delegate = self }

    func resolveCity() async throws -> CitySetting {
        let loc = try await location()
        let name: String, country: String?
        do {
            let items = try await MKReverseGeocodingRequest(location: loc)?.mapItems ?? []
            let item = items.first
            name = item?.addressRepresentations?.cityName ?? item?.name ?? String(format: "%.2f, %.2f", loc.coordinate.latitude, loc.coordinate.longitude)
            country = item?.addressRepresentations?.regionName
        } catch {
            name = String(format: "%.2f, %.2f", loc.coordinate.latitude, loc.coordinate.longitude)
            country = nil
        }
        return CitySetting(name: name, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, country: country)
    }

    private func location() async throws -> CLLocation {
        guard cont == nil else { throw LocationError.unavailable }
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError.denied
        default: break
        }
        return try await withCheckedThrowingContinuation { c in
            cont = c
            if manager.authorizationStatus == .notDetermined {
                waitingForAuth = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.waitingForAuth else { return }
            switch status {
            case .notDetermined: return
            case .denied, .restricted:
                self.waitingForAuth = false; self.finish(.failure(LocationError.denied))
            default:
                self.waitingForAuth = false; self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.finish(.success(l)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finish(.failure(denied ? LocationError.denied : error)) }
    }

    private func finish(_ r: Result<CLLocation, Error>) {
        guard let c = cont else { return }
        cont = nil
        c.resume(with: r)
    }
}

/// Поле настройки типа `city`: текущий город, поиск, результаты, «текущее местоположение».
struct CityPickerView: View {
    let label: String
    let current: CitySetting?
    let onSelect: (CitySetting) -> Void

    @StateObject private var model = CitySearchModel()
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(current.map { [$0.name, $0.country].compactMap { $0 }.joined(separator: ", ") } ?? "Not selected")
                    .foregroundStyle(.secondary)
            }
            TextField("Search for a city", text: $query)
                .onChange(of: query) { _, v in model.queryChanged(v) }
            if model.isLoading { ProgressView().controlSize(.small) }
            ForEach(Array(model.results.enumerated()), id: \.offset) { _, c in
                Button {
                    onSelect(c); query = ""; model.queryChanged("")
                } label: {
                    HStack {
                        Text(c.name)
                        if let k = c.country { Text(k).foregroundStyle(.secondary) }
                        Spacer()
                        Text(String(format: "%.2f, %.2f", c.latitude, c.longitude))
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let s = model.status {
                Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                model.useCurrentLocation { onSelect($0) }
            } label: {
                Label(model.isLocating ? "Locating…" : "Use Current Location", systemImage: "location")
            }
            .disabled(model.isLocating)
        }
    }
}
