# Компоненты Renderer

Дерево: `{"type": "...", "props": {...}, "children": [...]}` (`UINode`). Обязателен только `type`,
`props` и `children` можно опускать. Неизвестный `type`, неверные типы props
и глубина > 24 дают пунктирный плейсхолдер "?" без падения. Числа вне диапазона зажимаются.

## Общие props (любой компонент)
| prop | тип | дефолт | описание |
|---|---|---|---|
| padding | number | 0 | отступ, pt (0...4000) |
| width, height | number | нет | фиксированный размер, pt |
| opacity | number | 1 | 0...1 |

Если у `VStack`/`ZStack` заданы `width`/`height` и явный `alignment` (`leading`/`trailing`/`center`), весь блок прижимается в рамке в ту же сторону, а не только элементы внутри него. Без `alignment` блок по центру рамки.

## Цвета
`"accent"` (Theme.accentHex), `"primary"`, `"secondary"` или `"#RGB"`/`"#RRGGBB"`/`"#RRGGBBAA"`.
Неверное значение -> дефолт компонента. Шрифт всегда берётся из `Theme.fontDesign`.
Дефолтные размеры умножаются на коэффициент SizeClass (small 0.9, medium 1, large 1.15, extraLarge 1.3).
Веса: ultraLight, thin, light, regular, medium, semibold, bold, heavy, black.

## VStack / HStack / ZStack
Props: `spacing` (number, системный; не для ZStack), `alignment` (VStack: leading|center|trailing, дефолт leading;
HStack: top|center|bottom, дефолт center; ZStack: center|leading|trailing|top|bottom|topLeading|topTrailing|bottomLeading|bottomTrailing, дефолт center).
```json
{"type":"VStack","props":{"spacing":4,"alignment":"leading"},"children":[]}
```

## Spacer
Props: `minLength` (number, системный).
```json
{"type":"Spacer","props":{}}
```

## Text
Props: `text` (string, ""), `size` (number, 14), `weight` (string, regular), `color` (primary),
`align` (leading|center|trailing, leading), `lineLimit` (int 1...50, без лимита), `monospacedDigit` (bool, false).
```json
{"type":"Text","props":{"text":"78 %","size":32,"weight":"semibold","color":"accent"}}
```

## Image (SF Symbols)
Props: `systemName` (string, "questionmark.square.dashed"), `size` (number, 16), `weight` (regular), `color` (primary).
```json
{"type":"Image","props":{"systemName":"battery.100","size":20,"color":"#30D158"}}
```

## LinearBar
Props: `value` (0...1, 0; зажимается), `color` (accent), `trackColor` (secondary 25%), `height` (number, 8).
```json
{"type":"LinearBar","props":{"value":0.62,"height":6}}
```

## Ring
Кольцо от 12 часов по часовой. Дочерние элементы центрируются внутри.
Props: `value` (0...1, 0), `color` (accent), `trackColor`, `size` (56), `lineWidth` (size/8, мин. 3).
```json
{"type":"Ring","props":{"value":0.78,"color":"#30D158","size":64},"children":[{"type":"Image","props":{"systemName":"laptopcomputer"}}]}
```

## Gauge
Полукруг (дуга 180°); дочерние элементы внизу по центру.
Props: `value` (0...1, 0), `color`, `trackColor`, `size` (ширина, 80), `lineWidth` (size/9, мин. 4).
```json
{"type":"Gauge","props":{"value":0.4,"size":90},"children":[{"type":"Text","props":{"text":"40"}}]}
```

## SegmentedBar
Props: `value` (0...1, 0), `segments` (int 1...100, 10), `color`, `trackColor`, `height` (8), `spacing` (2).
```json
{"type":"SegmentedBar","props":{"value":0.5,"segments":8}}
```

## Sparkline
Мини-график без осей. Props: `values` (number[], до 500 точек, нечисловые пропускаются), `color`, `height` (28), `fill` (bool, false).
```json
{"type":"Sparkline","props":{"values":[1,3,2,5,4],"fill":true}}
```

## LineChart (Swift Charts)
Props: `values` (number[]), `color`, `height` (80), `area` (bool, false: градиентная заливка), `showAxes` (bool, true).
```json
{"type":"LineChart","props":{"values":[10,12,9,14],"area":true,"showAxes":false}}
```

## BarChart (Swift Charts)
Props: `values` (number[]), `labels` (string[], подписи оси X), `color`, `height` (80), `showAxes` (bool, false).
```json
{"type":"BarChart","props":{"values":[3,5,2],"labels":["Пн","Вт","Ср"]}}
```

## DigitalClock
Props: `timeZone` (IANA id или аббревиатура, системный пояс), `hour12` (bool, false), `showSeconds` (bool, false),
`size` (32), `weight` (medium), `color` (primary), `part` ("all"|"hour"|"minute", all: показать только часы или минуты),
`monospaced` (bool, false: моноширинный шрифт). Обновляется раз в секунду.
```json
{"type":"DigitalClock","props":{"timeZone":"Europe/Moscow","hour12":false,"showSeconds":true}}
```

## AnalogClock
Циферблат с цифрами, часовой/минутной/секундной стрелками (секундная оранжевая).
Props: `timeZone` (системный), `hour12` (bool, true: цифры 12,1..11; false: 24-часовой циферблат 24,2,4..22,
часовая стрелка делает оборот за сутки), `showSeconds` (bool, true), `size` (100), `color` (primary), `secondColor` (orange),
`numbers` ("all"|"quarters"|"none", all), `ticks` (bool, false: 60 рисок по кругу), `dots` (bool, false: 12 точек).
```json
{"type":"AnalogClock","props":{"timeZone":"Asia/Tokyo","hour12":true,"size":120}}
```
