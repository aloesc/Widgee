import Foundation
import WidgeeCore

/// Исходник виртуального ES-модуля "widgee" (и тот же набор как глобальный `widgee` для запасного варианта).
enum SDKModule {
    static let componentNames = ["VStack", "HStack", "ZStack", "Spacer", "Text", "Image", "LinearBar", "Ring",
                                 "Gauge", "SegmentedBar", "Sparkline", "LineChart", "BarChart",
                                 "DigitalClock", "AnalogClock"]

    static var source: String {
        var s = """
        const make = (type) => (props, ...children) => {
          const flat = children.flat(Infinity).filter((c) => c !== null && c !== undefined && c !== false);
          return { type, props: props ?? {}, children: flat };
        };
        export const defineWidget = (def) => def;
        export const system = (metric, opts) => ({ kind: "system", metric, interval: opts?.interval });
        export const timer = (seconds) => ({ kind: "timer", seconds });
        export const http = (url, opts) => ({ kind: "http", url, every: opts?.every });

        """
        for n in componentNames { s += "export const \(n) = make(\"\(n)\");\n" }
        return s
    }
}
