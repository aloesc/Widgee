import Foundation
import WidgeeCore

public struct WidgetPermissions: Codable, Equatable, Sendable {
    public var system: [String]
    public var network: [String]

    public init(system: [String] = [], network: [String] = []) {
        self.system = system; self.network = network
    }

    enum CodingKeys: String, CodingKey { case system, network }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        system = try c.decodeIfPresent([String].self, forKey: .system) ?? []
        network = try c.decodeIfPresent([String].self, forKey: .network) ?? []
    }
}

public struct WidgetSettingField: Codable, Equatable, Sendable {
    public var key: String
    public var type: String
    public var label: String
    public var `default`: JSONValue?
    /// Варианты для `select`.
    public var options: [String]?
    /// Условная видимость в панели настроек (хост всё равно передаёт виджету значения всех полей).
    public var showIf: SettingCondition?

    public init(key: String, type: String, label: String, default: JSONValue? = nil, options: [String]? = nil,
                showIf: SettingCondition? = nil) {
        self.key = key; self.type = type; self.label = label; self.default = `default`; self.options = options
        self.showIf = showIf
    }
}

/// Условие `showIf: { "key": "...", "equals": "..." }`: поле видно, пока значение поля `key` равно `equals`.
public struct SettingCondition: Codable, Equatable, Sendable {
    public var key: String
    public var equals: JSONValue

    public init(key: String, equals: JSONValue) { self.key = key; self.equals = equals }

    /// `values` — текущие значения настроек; пропуски заменяются значениями по умолчанию.
    public func isSatisfied(values: [String: JSONValue], fields: [WidgetSettingField]) -> Bool {
        let v = values[key] ?? fields.first { $0.key == key }?.default
        return v == equals
    }
}

extension WidgetSettingField {
    /// `#RRGGBB` (6 шестнадцатеричных цифр).
    public static func isValidHexColor(_ s: String) -> Bool {
        let u = Array(s.utf8)
        return u.count == 7 && u[0] == UInt8(ascii: "#") && u.dropFirst().allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }
    }
}

/// Значение настройки типа `city`: объект `{ name, latitude, longitude, country? }`.
public struct CitySetting: Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var country: String?

    public init(name: String, latitude: Double, longitude: Double, country: String? = nil) {
        self.name = name; self.latitude = latitude; self.longitude = longitude; self.country = country
    }

    /// nil, если значение не объект нужной формы или координаты вне диапазона.
    public init?(json: JSONValue?) {
        guard case .object(let o)? = json, let name = o["name"]?.stringValue,
              !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let lat = o["latitude"]?.numberValue, let lon = o["longitude"]?.numberValue,
              lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        let country: String?
        switch o["country"] {
        case nil, .null?: country = nil
        case .string(let c)?: country = c
        default: return nil
        }
        self.init(name: name, latitude: lat, longitude: lon, country: country)
    }

    public var json: JSONValue {
        var o: [String: JSONValue] = ["name": .string(name), "latitude": .number(latitude), "longitude": .number(longitude)]
        if let country { o["country"] = .string(country) }
        return .object(o)
    }
}

/// Готовый вариант виджета для галереи: имя, размер и значения настроек. `size` в ячейках («2x1») или S/M/L/XL.
public struct WidgetVariant: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var size: String
    public var settings: [String: JSONValue]

    public init(key: String, name: String, size: String, settings: [String: JSONValue] = [:]) {
        self.key = key; self.name = name; self.size = size; self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case key, name, size, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        size = WidgetManifest.canonicalSize(try c.decodeIfPresent(String.self, forKey: .size) ?? "M")
        settings = try c.decodeIfPresent([String: JSONValue].self, forKey: .settings) ?? [:]
    }
}

public enum WidgetManifestError: Error, Equatable, CustomStringConvertible, Sendable {
    case unreadable(String)
    case invalidJSON(String)
    case invalidField(String)
    case incompatibleSDK(required: String, host: String)

    public var description: String {
        switch self {
        case .unreadable(let m): "manifest.json cannot be read: \(m)"
        case .invalidJSON(let m): "manifest.json is invalid: \(m)"
        case .invalidField(let m): "manifest.json: \(m)"
        case .incompatibleSDK(let r, let h): "incompatible sdk \(r): host supports \(h) (same MAJOR, MINOR not higher than the host)"
        }
    }
}

public struct WidgetManifest: Codable, Equatable, Sendable {
    public static let allowedSizes: Set<String> = ["S", "M", "L", "XL"]

    /// Размеры в ячейках сетки («1x1», «2×1», …) приводятся к каноническим S/M/L/XL.
    static func canonicalSize(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "×", with: "x")
        switch t {
        case "1x1": return "S"
        case "2x1": return "M"
        case "2x2": return "L"
        case "4x2": return "XL"
        default: return raw
        }
    }
    public static let allowedSettingTypes: Set<String> = ["string", "number", "boolean", "select", "color", "city"]

    public var id: String
    public var name: String
    public var version: String
    public var author: String
    public var sdk: String
    public var sizes: [String]
    public var permissions: WidgetPermissions
    public var settings: [WidgetSettingField]
    /// Необязательные готовые варианты для галереи (карточки с предустановленными настройками).
    public var variants: [WidgetVariant]

    enum CodingKeys: String, CodingKey { case id, name, version, author, sdk, sizes, permissions, settings, variants }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        sdk = try c.decode(String.self, forKey: .sdk)
        sizes = (try c.decodeIfPresent([String].self, forKey: .sizes) ?? ["M"]).map(Self.canonicalSize)
        permissions = try c.decodeIfPresent(WidgetPermissions.self, forKey: .permissions) ?? WidgetPermissions()
        settings = try c.decodeIfPresent([WidgetSettingField].self, forKey: .settings) ?? []
        variants = try c.decodeIfPresent([WidgetVariant].self, forKey: .variants) ?? []
    }

    public init(id: String, name: String, version: String, author: String = "", sdk: String,
                sizes: [String] = ["M"], permissions: WidgetPermissions = .init(),
                settings: [WidgetSettingField] = [], variants: [WidgetVariant] = []) {
        self.id = id; self.name = name; self.version = version; self.author = author
        self.sdk = sdk; self.sizes = sizes; self.permissions = permissions; self.settings = settings
        self.variants = variants
    }

    /// Разбор и валидация манифеста.
    public static func parse(_ data: Data, hostSDK: String = WidgeeCore.sdkVersion) throws -> WidgetManifest {
        let m: WidgetManifest
        do {
            m = try JSONDecoder().decode(WidgetManifest.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw WidgetManifestError.invalidField("missing required field “\(key.stringValue)”")
        } catch let DecodingError.typeMismatch(_, ctx) {
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            throw WidgetManifestError.invalidField("wrong type for field “\(path)”")
        } catch {
            throw WidgetManifestError.invalidJSON(error.localizedDescription)
        }
        try m.validate(hostSDK: hostSDK)
        return m
    }

    public func validate(hostSDK: String = WidgeeCore.sdkVersion) throws {
        func bad(_ s: String) -> WidgetManifestError { .invalidField(s) }
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else { throw bad("empty id") }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw bad("empty name") }
        guard SemVer(version) != nil else { throw bad("version “\(version)” is not SemVer") }
        guard let sdkV = SemVer(sdk) else { throw bad("sdk “\(sdk)” is not SemVer") }
        guard let host = SemVer(hostSDK) else { throw bad("host sdk “\(hostSDK)” is not SemVer") }
        guard sdkV.major == host.major, sdkV.minor <= host.minor else {
            throw WidgetManifestError.incompatibleSDK(required: sdk, host: hostSDK)
        }
        if sizes.isEmpty { throw bad("sizes is empty") }
        for s in sizes where !Self.allowedSizes.contains(s) { throw bad("unknown size “\(s)”") }
        var keys = Set<String>()
        for f in settings {
            guard !f.key.isEmpty else { throw bad("empty key in settings") }
            guard keys.insert(f.key).inserted else { throw bad("duplicate key “\(f.key)” in settings") }
            guard Self.allowedSettingTypes.contains(f.type) else {
                throw bad("settings.\(f.key): unknown type “\(f.type)”")
            }
            if f.type == "select", let o = f.options {
                guard !o.isEmpty, !o.contains(where: { $0.isEmpty }) else {
                    throw bad("settings.\(f.key): options must be a non-empty list of non-empty strings")
                }
            }
            if f.type == "color" {
                guard let d = f.default?.stringValue, WidgetSettingField.isValidHexColor(d) else {
                    throw bad("settings.\(f.key): color requires a default in #RRGGBB format")
                }
            }
            if let c = f.showIf {
                guard c.key != f.key else { throw bad("settings.\(f.key): showIf refers to the field itself") }
                guard settings.contains(where: { $0.key == c.key }) else {
                    throw bad("settings.\(f.key): showIf refers to unknown field “\(c.key)”")
                }
                switch c.equals {
                case .string, .bool, .number: break
                default: throw bad("settings.\(f.key): showIf.equals must be a string, number or boolean")
                }
            }
            if f.type == "city", let d = f.default, d != .null, CitySetting(json: d) == nil {
                throw bad("settings.\(f.key): default for city must be { name, latitude, longitude, country? }")
            }
        }
        var variantKeys = Set<String>()
        for v in variants {
            guard !v.key.isEmpty, !v.key.contains("/") else { throw bad("variants: key must be a non-empty string without “/”") }
            guard variantKeys.insert(v.key).inserted else { throw bad("variants: duplicate key “\(v.key)”") }
            guard !v.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw bad("variants.\(v.key): empty name") }
            guard Self.allowedSizes.contains(v.size), sizes.contains(v.size) else {
                throw bad("variants.\(v.key): size “\(v.size)” is not one of the widget's sizes")
            }
            for k in v.settings.keys where !keys.contains(k) {
                throw bad("variants.\(v.key): unknown setting “\(k)”")
            }
        }
        for d in permissions.network {
            guard !d.isEmpty, !d.contains("/"), !d.contains(":"), !d.contains(" ") else {
                throw bad("permissions.network: “\(d)” must be a domain name")
            }
        }
    }
}
