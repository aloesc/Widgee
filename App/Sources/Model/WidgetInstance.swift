import Foundation
import Layout
import WidgeeCore

/// Размеры как у Apple. Внутренние имена S/M/L/XL (хранятся в config.json), пользователю показываются в ячейках.
enum WidgetSizePreset: String, CaseIterable, Codable, Sendable {
    case S, M, L, XL

    var size: CGSize {
        switch self {
        case .S: CGSize(width: 170, height: 170)
        case .M: CGSize(width: 360, height: 170)
        case .L: CGSize(width: 360, height: 376)
        case .XL: CGSize(width: 720, height: 376)
        }
    }

    /// Размер в ячейках сетки (колонки × строки).
    var cells: (cols: Int, rows: Int) {
        switch self {
        case .S: (1, 1)
        case .M: (2, 1)
        case .L: (2, 2)
        case .XL: (4, 2)
        }
    }

    /// Подпись для пользователя: «1×1», «2×1», «2×2», «4×2».
    var cellLabel: String { "\(cells.cols)×\(cells.rows)" }

    var sizeClass: SizeClass {
        switch self {
        case .S: .small
        case .M: .medium
        case .L: .large
        case .XL: .extraLarge
        }
    }

    /// Ближайший пресет к произвольному размеру (по соотношению сторон и площади), для `ctx.size.sizeClass`.
    static func nearest(to size: CGSize) -> WidgetSizePreset {
        guard size.width > 0, size.height > 0 else { return .S }
        func d(_ p: WidgetSizePreset) -> Double {
            abs(log(Double(size.width / p.size.width))) + abs(log(Double(size.height / p.size.height)))
        }
        return allCases.min { d($0) < d($1) } ?? .M
    }

    init(sizeClass: SizeClass) {
        switch sizeClass {
        case .small: self = .S
        case .medium: self = .M
        case .large: self = .L
        case .extraLarge: self = .XL
        }
    }
}

/// Внешний вид текста: Auto следует теме системы, Light/Dark принудительно задают светлую/тёмную схему
/// (Light = светлая схема, тёмный текст; Dark = тёмная схема, светлый текст).
enum TextAppearance: String, Codable, CaseIterable, Sendable {
    case auto, light, dark
}

/// Экземпляр виджета на рабочем столе. Позиция хранится как смещение левого нижнего угла окна
/// от левого нижнего угла экрана `displayID`; если экрана нет, окно показывается на главном.
struct WidgetInstance: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var widgetID: String
    var sizeClass: SizeClass
    var width: Double
    var height: Double
    var displayID: UInt32?
    var offsetX: Double
    var offsetY: Double
    var background: BackgroundStyle
    var cornerRadius: Double
    var fontDesign: FontDesign
    var accentHex: String
    var settings: [String: JSONValue]
    /// nil = Auto (поле опционально: старые config.json читаются без него).
    var textAppearance: TextAppearance?
    /// Выравнивание содержимого внутри виджета; nil = Auto (собственная раскладка виджета).
    var alignment: ContentAlignment?
    /// Имя семейства установленного шрифта; nil = по `fontDesign` (старые config.json читаются без поля).
    var fontFamily: String?
    /// Множитель размера текста; nil = Auto (максимальный кегль, который влезает). Старые config.json читаются без поля.
    var textScale: Double?
    /// Вес текста (ultraLight...black); nil = Auto. Старые config.json читаются без поля.
    var fontWeight: String?

    var size: CGSize { CGSize(width: width, height: height) }

    init(id: UUID = UUID(), widgetID: String, preset: WidgetSizePreset = .M,
         displayID: UInt32? = nil, offsetX: Double = 80, offsetY: Double = 80,
         background: BackgroundStyle = .liquidGlass, cornerRadius: Double = 22,
         fontDesign: FontDesign = .standard, accentHex: String = "#0A84FF",
         settings: [String: JSONValue] = [:]) {
        self.id = id
        self.widgetID = widgetID
        self.sizeClass = preset.sizeClass
        self.width = preset.size.width
        self.height = preset.size.height
        self.displayID = displayID
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.background = background
        self.cornerRadius = cornerRadius
        self.fontDesign = fontDesign
        self.accentHex = accentHex
        self.settings = settings
    }

    mutating func apply(preset: WidgetSizePreset) {
        sizeClass = preset.sizeClass
        width = preset.size.width
        height = preset.size.height
    }
}

struct AppConfig: Codable, Equatable, Sendable {
    var version: Int = 1
    var instances: [WidgetInstance] = []
    /// Прилипание и сетка; старые config.json без поля читаются с настройками по умолчанию.
    var layout = LayoutSettings()

    init(version: Int = 1, instances: [WidgetInstance] = [], layout: LayoutSettings = LayoutSettings()) {
        self.version = version; self.instances = instances; self.layout = layout
    }

    private enum CodingKeys: String, CodingKey { case version, instances, layout }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        instances = try c.decode([WidgetInstance].self, forKey: .instances)
        layout = (try? c.decodeIfPresent(LayoutSettings.self, forKey: .layout)) ?? LayoutSettings()
    }
}

/// В SwiftUI тоже есть `GridLayout`; псевдоним отсюда (файл без импорта SwiftUI) однозначен.
typealias SnapGridLayout = GridLayout
