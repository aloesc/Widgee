import { defineWidget, VStack, HStack, Spacer, Text, DigitalClock, AnalogClock, timer } from "widgee";

function dateParts(nowMs, tz) {
  const d = new Date(typeof nowMs === "number" ? nowMs : Date.now());
  try {
    const a = tz ? { timeZone: tz } : {};
    return [d.toLocaleDateString(undefined, { weekday: "long", ...a }),
            d.toLocaleDateString(undefined, { day: "numeric", month: "short", ...a })];
  } catch (e) {
    return [d.toDateString(), ""];
  }
}

function dateText(nowMs, tz) {
  const d = new Date(typeof nowMs === "number" ? nowMs : Date.now());
  try {
    const opts = { weekday: "long", day: "numeric", month: "long" };
    if (tz) opts.timeZone = tz;
    return d.toLocaleDateString(undefined, opts);
  } catch (e) {
    return d.toDateString();
  }
}

// Выравнивание содержимого (ctx.theme.alignment): auto | left | center | right.
// Возвращает параметры раскладки; auto = собственная раскладка виджета.
function alignInfo(ctx) {
  const a = ctx && ctx.theme ? ctx.theme.alignment : "auto";
  const mode = a === "left" || a === "center" || a === "right" ? a : "auto";
  const v = mode === "left" ? "leading" : mode === "right" ? "trailing" : "center"; // VStack alignment / Text.align
  return { mode, v, left: mode === "left", right: mode === "right", centered: mode === "center" || mode === "auto" };
}

const STYLES = ["digital", "analog", "bold", "stacked", "minimal", "mono", "analog-minimal", "analog-dots", "analog-seconds"];

export default defineWidget({
  sources: { now: timer(30) },
  render(ctx) {
    const s = ctx.settings || {};
    const style = STYLES.indexOf(s.style) >= 0 ? s.style : "digital";
    const isAnalog = style.indexOf("analog") === 0;
    // Параметры циферблата для аналоговых вариантов (по умолчанию — текущий вид).
    const face0 = style === "analog-minimal" ? { numbers: "none", ticks: true }
      : style === "analog-dots" ? { numbers: "none", dots: true }
      : style === "analog-seconds" ? { numbers: "quarters", ticks: true }
      : { numbers: "all" };
    const hour12 = s.hour12 === true;
    const showSeconds = style === "analog-seconds" ? true : s.showSeconds !== false;
    const tz = typeof s.timezone === "string" && s.timezone.trim() !== "" ? s.timezone.trim() : undefined;
    const sc = ctx.size.sizeClass;
    const w = ctx.size.width, h = ctx.size.height;
    const now = ctx.data && ctx.data.now ? ctx.data.now.now : undefined;
    const date = dateText(now, tz);
    const parts = dateParts(now, tz);
    const pad = 14;
    const al = alignInfo(ctx);

    const aw = Math.max(40, w - pad * 2), ah = Math.max(40, h - pad * 2);

    if (isAnalog) {
      const large = style === "analog-seconds";
      const wide = !large && aw >= ah * 1.45 && aw >= 300;
      const fit = (n) => Math.max(10, Math.min(n, 400));
      if (wide) {
        // Дата справа, циферблат на всю высоту.
        const face = Math.max(60, Math.min(ah, aw * 0.5));
        const textW = aw - face - 20;
        const big = fit(Math.min(face * 0.2, textW / 7));
        const face_ = AnalogClock({ timeZone: tz, hour12: true, showSeconds, size: face, ...face0 });
        const info = VStack({ spacing: Math.max(2, big * 0.15), alignment: al.right ? "trailing" : "leading", width: textW },
          Text({ text: parts[0], size: big, weight: "semibold", color: "accent", align: al.right ? "trailing" : "leading", lineLimit: 1 }),
          Text({ text: parts[1], size: big * 0.8, align: al.right ? "trailing" : "leading", lineLimit: 1 }),
          tz ? Text({ text: tz, size: Math.max(10, big * 0.45), color: "secondary", align: al.right ? "trailing" : "leading", lineLimit: 1 }) : null);
        // left: циферблат у левого края, дата справа; right: зеркально; center/auto: блок по центру.
        if (al.left) return HStack({ spacing: 20, alignment: "center", padding: pad, width: w, height: h }, face_, info, Spacer());
        if (al.right) return HStack({ spacing: 20, alignment: "center", padding: pad, width: w, height: h }, Spacer(), info, face_);
        return HStack({ spacing: 20, alignment: "center", padding: pad, width: w, height: h }, Spacer(), face_, info, Spacer());
      }
      // Дата под циферблатом (если есть место по высоте).
      const dsize = fit(Math.min(aw / 14, ah / 12));
      const withDate = !large && ah >= 200 && aw >= 150;
      const face = Math.max(60, Math.min(large ? Math.max(aw, ah) : aw, withDate ? ah - dsize * 1.6 - 8 : ah));
      return VStack({ spacing: 8, alignment: al.v, padding: pad, width: w, height: h },
        Spacer(), AnalogClock({ timeZone: tz, hour12: true, showSeconds, size: face, ...face0 }),
        withDate ? Text({ text: date, size: dsize, color: "secondary", align: al.v, lineLimit: 1 }) : null,
        Spacer());
    }

    const bold = style === "bold", mono = style === "mono", minimal = style === "minimal", stacked = style === "stacked";
    const weight = bold ? "heavy" : mono ? "regular" : minimal ? "ultraLight" : "light";
    // Ширина строки времени в em (цифры ~0.58, двоеточие ~0.3, AM/PM ~1.7).
    const dw = mono ? 0.62 : bold ? 0.64 : 0.58;
    const em = (showSeconds ? 6 : 4) * dw + (showSeconds ? 2 : 1) * 0.3 + (hour12 ? 1.8 : 0);
    const showDate = !minimal && ah >= 90;
    const showTz = !minimal && !!tz && ah >= 160;
    const dateStr = (aw > 420 ? date : parts[0] + (parts[1] ? ", " + parts[1] : ""));
    const dsizeOf = (b) => Math.max(11, Math.min(b * 0.28, aw * 0.9 / Math.max(8, dateStr.length * 0.58), 60));
    if (stacked) {
      // Часы над минутами: ширина ~2 цифры, ограничение по высоте двух строк.
      const sb = Math.max(14, Math.min(aw * 0.9 / 1.3, ah * (showDate ? 0.36 : 0.45), 400));
      const ds = dsizeOf(sb * 1.4);
      return VStack({ spacing: 0, alignment: al.v, padding: pad, width: w, height: h },
        Spacer(),
        DigitalClock({ timeZone: tz, hour12, part: "hour", size: sb, weight: "semibold", color: "primary" }),
        DigitalClock({ timeZone: tz, part: "minute", size: sb, weight: "light", color: "accent" }),
        showDate ? Text({ text: dateStr, size: ds, color: "secondary", weight: "medium", align: al.v, lineLimit: 1 }) : null,
        Spacer());
    }
    // Время: <= 90% ширины и <= ~40% высоты (с датой) или ~70% (без даты).
    let big = Math.min(aw * 0.9 / em, ah * (showDate ? 0.42 : 0.7), 400);
    big = Math.max(14, big);
    const dsize = dsizeOf(big);
    return VStack({ spacing: Math.max(2, big * 0.06), alignment: al.v, padding: pad, width: w, height: h },
      Spacer(),
      DigitalClock({ timeZone: tz, hour12, showSeconds, size: big, weight, monospaced: mono, color: "primary" }),
      showDate ? Text({ text: dateStr, size: dsize, color: "accent", weight: bold ? "bold" : "medium", align: al.v, lineLimit: 1 }) : null,
      showTz ? Text({ text: tz, size: Math.max(10, dsize * 0.7), color: "secondary", align: al.v, lineLimit: 1 }) : null,
      Spacer());
  },
});
