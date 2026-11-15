// Widgee SDK 0.1 — типы виртуального модуля "widgee".
declare module "widgee" {
  export type Color = "accent" | "primary" | "secondary" | (string & {}); // "#RGB" | "#RRGGBB" | "#RRGGBBAA"
  export type Weight = "ultraLight" | "thin" | "light" | "regular" | "medium" | "semibold" | "bold" | "heavy" | "black";

  export type SizeClass = "small" | "medium" | "large" | "extraLarge";

  export interface UINode {
    type: string;
    props: Record<string, unknown>;
    children: UINode[];
  }
  export type Child = UINode | null | undefined | false | Child[];

  /** Общие props любого компонента. */
  export interface CommonProps {
    padding?: number;
    width?: number;
    height?: number;
    opacity?: number;
  }

  export interface StackProps extends CommonProps { spacing?: number }
  export interface VStackProps extends StackProps { alignment?: "leading" | "center" | "trailing" }
  export interface HStackProps extends StackProps { alignment?: "top" | "center" | "bottom" }
  export interface ZStackProps extends CommonProps {
    alignment?: "center" | "leading" | "trailing" | "top" | "bottom"
      | "topLeading" | "topTrailing" | "bottomLeading" | "bottomTrailing";
  }
  export interface SpacerProps extends CommonProps { minLength?: number }
  export interface TextProps extends CommonProps {
    text?: string; size?: number; weight?: Weight; color?: Color;
    align?: "leading" | "center" | "trailing"; lineLimit?: number; monospacedDigit?: boolean;
    /** Auto: самый крупный кегль, который влезает в коробку width x height (обязательны оба). Игнорируется при ctx.theme.textScale != null. */
    fit?: boolean;
  }
  export interface ImageProps extends CommonProps {
    /** Имя SF Symbol. */
    systemName?: string; size?: number; weight?: Weight; color?: Color;
  }
  export interface LinearBarProps extends CommonProps {
    value?: number; color?: Color; trackColor?: Color; height?: number;
  }
  export interface RingProps extends CommonProps {
    value?: number; color?: Color; trackColor?: Color; size?: number; lineWidth?: number;
  }
  export interface GaugeProps extends RingProps {}
  export interface SegmentedBarProps extends CommonProps {
    value?: number; segments?: number; color?: Color; trackColor?: Color; height?: number; spacing?: number;
  }
  export interface SparklineProps extends CommonProps {
    values?: number[]; color?: Color; height?: number; fill?: boolean;
  }
  export interface LineChartProps extends CommonProps {
    values?: number[]; color?: Color; height?: number; area?: boolean; showAxes?: boolean;
  }
  export interface BarChartProps extends CommonProps {
    values?: number[]; labels?: string[]; color?: Color; height?: number; showAxes?: boolean;
  }
  export interface DigitalClockProps extends CommonProps {
    timeZone?: string; hour12?: boolean; showSeconds?: boolean; size?: number; weight?: Weight; color?: Color;
    part?: "all" | "hour" | "minute"; monospaced?: boolean;
    /** Как Text.fit: вписать в коробку width x height (size игнорируется). */
    fit?: boolean; align?: "leading" | "center" | "trailing";
  }
  export interface AnalogClockProps extends CommonProps {
    timeZone?: string; hour12?: boolean; showSeconds?: boolean; size?: number; color?: Color; secondColor?: Color;
    numbers?: "all" | "quarters" | "none"; ticks?: boolean; dots?: boolean;
  }

  export function VStack(props?: VStackProps | null, ...children: Child[]): UINode;
  export function HStack(props?: HStackProps | null, ...children: Child[]): UINode;
  export function ZStack(props?: ZStackProps | null, ...children: Child[]): UINode;
  export function Spacer(props?: SpacerProps | null): UINode;
  export function Text(props?: TextProps | null): UINode;
  export function Image(props?: ImageProps | null): UINode;
  export function LinearBar(props?: LinearBarProps | null): UINode;
  export function Ring(props?: RingProps | null, ...children: Child[]): UINode;
  export function Gauge(props?: GaugeProps | null, ...children: Child[]): UINode;
  export function SegmentedBar(props?: SegmentedBarProps | null): UINode;
  export function Sparkline(props?: SparklineProps | null): UINode;
  export function LineChart(props?: LineChartProps | null): UINode;
  export function BarChart(props?: BarChartProps | null): UINode;
  export function DigitalClock(props?: DigitalClockProps | null): UINode;
  export function AnalogClock(props?: AnalogClockProps | null): UINode;

  // ---- Метрики (значения ctx.data для system-источников) ----
  export interface CPUMetrics { total: number; perCore: number[]; user: number; system: number }
  export interface RAMMetrics {
    total: number; used: number; wired: number; compressed: number; free: number; swapUsed: number; swapTotal: number;
  }
  export interface DiskMetrics { total: number; free: number }
  export interface NetworkMetrics { downBytesPerSec: number; upBytesPerSec: number }
  export interface BatteryMetrics { level: number; isCharging: boolean; isPluggedIn: boolean }
  export interface ProcessEntry { pid: number; name: string; cpu: number; memoryBytes: number }

  export interface MetricMap {
    cpu: CPUMetrics;
    ram: RAMMetrics;
    disk: DiskMetrics;
    network: NetworkMetrics;
    battery: BatteryMetrics | null;
    processes: ProcessEntry[];
    temperature: number | null;
    fans: number[] | null;
    gpu: number | null;
  }
  export type MetricName = keyof MetricMap;

  // ---- Источники данных ----
  export interface SystemSource<M extends MetricName = MetricName> { kind: "system"; metric: M; interval?: number }
  export interface TimerSource { kind: "timer"; seconds: number }
  export interface HttpSource { kind: "http"; url: string; every?: number }
  export type Source = SystemSource | TimerSource | HttpSource;

  /** Метрика должна быть в manifest.permissions.system. interval, с: 0.5...3600 (по умолчанию 2). */
  export function system<M extends MetricName>(metric: M, options?: { interval?: number }): SystemSource<M>;
  /** seconds, с: 1...86400. Значение: { now: мс с эпохи, tick: n }. */
  export function timer(seconds: number): TimerSource;
  /** Только https; хост должен быть в manifest.permissions.network. every, с: 60...86400 (по умолчанию 600). */
  export function http(url: string, options?: { every?: number }): HttpSource;

  export interface TimerData { now: number; tick: number }
  export interface HttpData<T = unknown> { value: T; updatedAt: number; stale: boolean }

  /** Тип значения ctx.data[key] для источника. До первого значения — null. */
  export type SourceData<S> =
    S extends SystemSource<infer M> ? MetricMap[M] | null :
    S extends TimerSource ? TimerData | null :
    S extends HttpSource ? HttpData | null :
    never;

  // ---- Контекст и виджет ----
  /**
   * Выравнивание содержимого, выбранное пользователем для экземпляра виджета.
   * "auto" — собственная раскладка виджета; "left" / "center" / "right" — виджет ОБЯЗАН
   * выровнять содержимое соответственно.
   */
  export type ContentAlignment = "auto" | "left" | "center" | "right";

  export type FontWeight = "ultraLight" | "thin" | "light" | "regular" | "medium" | "semibold" | "bold" | "heavy" | "black";

  export interface Theme {
    cornerRadius: number;
    fontDesign: "standard" | "rounded" | "monospaced" | "serif";
    accentHex: string;
    isDark: boolean;
    /** auto = собственная раскладка; left/center/right — виджет обязан выровнять содержимое. */
    alignment: ContentAlignment;
    /** Имя семейства выбранного пользователем шрифта (напр. "Georgia"); отсутствует = шрифт по fontDesign. Рендерер сам применяет шрифт. */
    fontFamily?: string;
    /** Ручной множитель размера текста (0.25...4); null/отсутствует = Auto: используйте fit с коробкой. Хост сам умножает все размеры. */
    textScale?: number | null;
    /** Вес текста, выбранный пользователем; null/отсутствует = Auto (собственные веса). Когда задан, хост применяет его ко всему тексту: виджеты ничего делать не обязаны. */
    fontWeight?: FontWeight | null;
  }

  /** Значение настройки типа "city" в manifest.settings. */
  export interface City { name: string; latitude: number; longitude: number; country?: string }
  /**
   * Типы полей manifest.settings: "string" | "number" | "boolean" | "select" (options) | "city" |
   * "color" (значение: строка "#RRGGBB"; default обязателен).
   * Необязательное showIf: { key, equals } скрывает поле в панели настроек, пока значение поля `key` не равно `equals`
   * (виджету значения всех полей приходят всегда).
   */
  export interface SettingField {
    key: string;
    type: "string" | "number" | "boolean" | "select" | "color" | "city";
    label: string;
    default?: SettingValue;
    options?: string[];
    showIf?: { key: string; equals: string | number | boolean };
  }
  /**
   * Готовая карточка для галереи (manifest.json → "variants"): имя, размер в ячейках ("1x1", "2x1", "2x2", "4x2")
   * и значения настроек. `size` должен входить в manifest.sizes, ключи settings — быть объявлены в manifest.settings.
   */
  export interface WidgetVariant {
    key: string;
    name: string;
    size: "1x1" | "2x1" | "2x2" | "4x2";
    settings?: Settings;
  }
  export type SettingValue = string | number | boolean | null | City;
  export type Settings = Record<string, SettingValue>;

  export interface RenderContext<S extends Record<string, Source> = Record<string, Source>> {
    size: { width: number; height: number; sizeClass: SizeClass };
    theme: Theme;
    settings: Settings;
    data: { [K in keyof S]: SourceData<S[K]> };
  }

  export interface WidgetDefinition<S extends Record<string, Source> = Record<string, Source>> {
    /**
     * Не более 8 источников. Может быть функцией `(settings) => ({...})`: хост вызывает её при загрузке
     * и заново при каждом изменении settings (источники пересоздаются, данные сбрасываются в null).
     * Права (permissions.network и т. д.) проверяются на итоговых URL.
     */
    sources?: S | ((settings: Settings) => S);
    /** Чистая функция: без побочных эффектов, укладывается в таймаут. */
    render(ctx: RenderContext<S>): UINode;
  }

  export function defineWidget<S extends Record<string, Source> = {}>(def: WidgetDefinition<S>): WidgetDefinition<S>;
}
