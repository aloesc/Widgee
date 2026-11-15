import { defineWidget, VStack, HStack, Spacer, Text, Image, http } from "widgee";

const DASH = "—";
const WHITE = "#FFFFFF";
const SOFT = "#FFFFFFB8";
const DEFAULT_CITY = { name: "Moscow", latitude: 55.7558, longitude: 37.6176 };

// WMO weather_code -> [описание, символ (день), символ (ночь)]
const WMO = {
  0: ["Clear sky", "sun.max.fill", "moon.stars.fill"],
  1: ["Mainly clear", "sun.max.fill", "moon.fill"],
  2: ["Partly cloudy", "cloud.sun.fill", "cloud.moon.fill"],
  3: ["Overcast", "cloud.fill", "cloud.fill"],
  45: ["Fog", "cloud.fog.fill", "cloud.fog.fill"],
  48: ["Rime fog", "cloud.fog.fill", "cloud.fog.fill"],
  51: ["Light drizzle", "cloud.drizzle.fill", "cloud.drizzle.fill"],
  53: ["Drizzle", "cloud.drizzle.fill", "cloud.drizzle.fill"],
  55: ["Dense drizzle", "cloud.drizzle.fill", "cloud.drizzle.fill"],
  56: ["Freezing drizzle", "cloud.sleet.fill", "cloud.sleet.fill"],
  57: ["Dense freezing drizzle", "cloud.sleet.fill", "cloud.sleet.fill"],
  61: ["Light rain", "cloud.rain.fill", "cloud.rain.fill"],
  63: ["Rain", "cloud.rain.fill", "cloud.rain.fill"],
  65: ["Heavy rain", "cloud.heavyrain.fill", "cloud.heavyrain.fill"],
  66: ["Freezing rain", "cloud.sleet.fill", "cloud.sleet.fill"],
  67: ["Heavy freezing rain", "cloud.sleet.fill", "cloud.sleet.fill"],
  71: ["Light snow", "cloud.snow.fill", "cloud.snow.fill"],
  73: ["Snow", "cloud.snow.fill", "cloud.snow.fill"],
  75: ["Heavy snow", "cloud.snow.fill", "cloud.snow.fill"],
  77: ["Snow grains", "cloud.snow.fill", "cloud.snow.fill"],
  80: ["Light showers", "cloud.rain.fill", "cloud.rain.fill"],
  81: ["Showers", "cloud.rain.fill", "cloud.rain.fill"],
  82: ["Violent showers", "cloud.heavyrain.fill", "cloud.heavyrain.fill"],
  85: ["Snow showers", "cloud.snow.fill", "cloud.snow.fill"],
  86: ["Heavy snow showers", "cloud.snow.fill", "cloud.snow.fill"],
  95: ["Thunderstorm", "cloud.bolt.fill", "cloud.bolt.fill"],
  96: ["Thunderstorm, hail", "cloud.bolt.rain.fill", "cloud.bolt.rain.fill"],
  99: ["Thunderstorm, heavy hail", "cloud.bolt.rain.fill", "cloud.bolt.rain.fill"],
};

function wmo(code, isDay) {
  const e = WMO[code];
  if (!e) return { text: DASH, symbol: "cloud.fill" };
  return { text: e[0], symbol: isDay === false ? e[2] : e[1] };
}

function symbolColor(symbol) {
  if (symbol.indexOf("sun") === 0) return "#FFD60A";
  if (symbol.indexOf("moon") === 0) return "#FFE9A8";
  return WHITE;
}

const isNum = (v) => typeof v === "number" && isFinite(v);
const deg = (v) => (isNum(v) ? Math.round(v) + "°" : DASH);
const num = (a, i) => (Array.isArray(a) && isNum(a[i]) ? a[i] : null);

function validCity(c) {
  return c && typeof c === "object" && typeof c.name === "string" && isNum(c.latitude) && isNum(c.longitude)
    ? c : DEFAULT_CITY;
}

function forecastURL(s) {
  const c = validCity(s && s.city);
  let url = "https://api.open-meteo.com/v1/forecast?latitude=" + c.latitude + "&longitude=" + c.longitude +
    "&current=temperature_2m,weather_code,is_day" +
    "&hourly=temperature_2m,weather_code" +
    "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
    "&timezone=auto&forecast_days=5";
  if (s && s.units === "fahrenheit") url += "&temperature_unit=fahrenheit";
  return url;
}

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function dayName(iso, index) {
  if (index === 0) return "Today";
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso));
  if (!m) return DASH;
  return DAYS[new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getDay()];
}

function hourly(v, count) {
  const h = v && v.hourly;
  if (!h || !Array.isArray(h.time)) return [];
  const nowKey = v.current && typeof v.current.time === "string" ? v.current.time.slice(0, 13) : "";
  let start = h.time.findIndex((t) => typeof t === "string" && t.slice(0, 13) >= nowKey);
  if (start < 0) start = 0;
  const out = [];
  for (let i = start; i < h.time.length && out.length < count; i++) {
    const hour = Number(String(h.time[i]).slice(11, 13));
    out.push({
      label: out.length === 0 ? "Now" : String(hour),
      temp: num(h.temperature_2m, i),
      info: wmo(num(h.weather_code, i), hour >= 6 && hour < 20),
    });
  }
  return out;
}

function daily(v) {
  const d = v && v.daily;
  if (!d || !Array.isArray(d.time)) return [];
  return d.time.slice(0, 5).map((t, i) => ({
    label: dayName(t, i),
    info: wmo(num(d.weather_code, i), true),
    max: num(d.temperature_2m_max, i),
    min: num(d.temperature_2m_min, i),
  }));
}

function hourCell(h, size, w) {
  return VStack({ spacing: 4, alignment: "center", width: w },
    Text({ text: h.label, size: size - 2, color: SOFT, align: "center", lineLimit: 1, height: size + 2 }),
    Image({ systemName: h.info.symbol, size: size + 4, color: symbolColor(h.info.symbol), width: size + 10, height: size + 10 }),
    Text({ text: deg(h.temp), size, weight: "medium", color: WHITE, align: "center", lineLimit: 1, height: size + 4 }));
}

function dayRow(d, size) {
  return HStack({ spacing: 8 },
    Text({ text: d.label, size, color: WHITE, width: 56, align: "leading", lineLimit: 1 }),
    Image({ systemName: d.info.symbol, size: size + 2, color: symbolColor(d.info.symbol), width: 28 }),
    Spacer(),
    Text({ text: deg(d.min), size, color: SOFT, width: 40, align: "trailing", monospacedDigit: true }),
    Text({ text: deg(d.max), size, weight: "medium", color: WHITE, width: 40, align: "trailing", monospacedDigit: true }));
}

// Выравнивание содержимого (ctx.theme.alignment): auto | left | center | right.
// Возвращает параметры раскладки; auto = собственная раскладка виджета.
function alignInfo(ctx) {
  const a = ctx && ctx.theme ? ctx.theme.alignment : "auto";
  const mode = a === "left" || a === "center" || a === "right" ? a : "auto";
  const v = mode === "left" ? "leading" : mode === "right" ? "trailing" : "center"; // VStack alignment / Text.align
  return { mode, v, left: mode === "left", right: mode === "right", centered: mode === "center" || mode === "auto" };
}

// Текст рисуется fit-кеглем в коробке w x h (pt). Ручной «Text size» (ctx.theme.textScale) применяет хост.
const T = (o, w, h) => (w > 0 && h > 0 ? { ...o, fit: true, width: Math.floor(w), height: Math.floor(h) } : o);

const STYLES = ["default", "compact", "hourly", "forecast", "big"];
const fc = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

// Горизонтальная строка с учётом выравнивания: auto/center — по центру, left — к левому краю, right — к правому.
function flow(c, spacing, ...items) {
  const al = c.al;
  if (al.left) return HStack({ spacing, alignment: "center" }, ...items, Spacer());
  if (al.right) return HStack({ spacing, alignment: "center" }, Spacer(), ...items);
  return HStack({ spacing, alignment: "center" }, Spacer(), ...items, Spacer());
}

function staleNode(c, size) {
  return c.stale ? Text({ text: "Updated earlier", size, color: SOFT, align: c.cv, lineLimit: 1 }) : null;
}

function frame(c, ...children) {
  return VStack({ spacing: 4, alignment: c.cv, padding: 14, width: c.w, height: c.h }, ...children);
}

function compactView(c) {
  const t = fc(Math.min(c.ah * (c.ah >= 130 ? 0.34 : 0.42), c.aw / 3.3), 16, 120);
  const cs = fc(t * 0.38, 11, 30);
  const desc = c.ah >= 130;
  const av = c.ah - 4 * (desc ? 2 : 1), cb = av * (desc ? 0.24 : 0.3), tb = av * (desc ? 0.52 : 0.7), db = av * 0.24;
  const isz = tb * 0.9;
  return frame(c, Spacer(),
    Text(T({ text: c.city.name, size: cs, weight: "semibold", color: WHITE, align: c.cv, lineLimit: 1 }, c.aw, cb)),
    flow(c, t * 0.18,
      Image({ systemName: c.info.symbol, size: isz, color: symbolColor(c.info.symbol) }),
      Text(T({ text: c.temp, size: t, weight: "light", color: WHITE, align: "center", lineLimit: 1 }, Math.max(20, c.aw - isz - t * 0.18), tb))),
    desc ? Text(T({ text: c.info.text, size: cs * 0.9, color: SOFT, align: c.cv, lineLimit: 1 }, c.aw, db)) : null,
    Spacer());
}

function bigView(c) {
  const t = fc(Math.min(c.aw / 2.8, c.ah * (c.ah >= 120 ? 0.6 : 0.85)), 24, 320);
  const cs = fc(t * 0.16, 11, 28);
  const full = c.ah >= 120;
  const bv = c.ah - 4 * (full ? 2 : 0), bc = bv * 0.2, bt = full ? bv * 0.6 : bv;
  return frame(c, Spacer(),
    full ? Text(T({ text: c.city.name, size: cs, weight: "semibold", color: WHITE, align: c.cv, lineLimit: 1 }, c.aw, bc)) : null,
    Text(T({ text: c.temp, size: t, weight: "thin", color: WHITE, align: c.cv, lineLimit: 1 }, c.aw, bt)),
    full ? Text(T({ text: c.info.text, size: cs, color: SOFT, align: c.cv, lineLimit: 1 }, c.aw, bc)) : null,
    staleNode(c, 11), Spacer());
}

function headerRow(c, size) {
  return flow(c, 8,
    Image({ systemName: c.info.symbol, size: size * 1.1, color: symbolColor(c.info.symbol) }),
    Text(T({ text: c.city.name, size: size * 0.55, weight: "semibold", color: WHITE, align: "center", lineLimit: 1 }, c.aw * 0.4, size * 0.9)),
    Text(T({ text: c.temp, size, weight: "light", color: WHITE, align: "center", lineLimit: 1 }, c.aw * 0.3, size * 1.2)));
}

function hourlyView(c) {
  const withHead = c.ah >= 130;
  const n = fc(Math.floor(c.aw / 46), 3, 12);
  const hf = fc(Math.min(c.aw / (n * 46), (c.ah - (withHead ? 44 : 0)) / 70), 0.85, 1.8);
  const hrs = hourly(c.v, n);
  const size = 13 * hf;
  const cw = Math.floor(c.aw / n);
  return frame(c, Spacer(),
    withHead ? headerRow(c, fc(c.ah * 0.16, 20, 44)) : null,
    withHead ? Spacer({ minLength: 4 }) : null,
    hrs.length ? HStack({ spacing: 0, alignment: "top" }, ...hrs.map((hh) => hourCell(hh, size, cw)))
      : Text({ text: DASH, size: 18, color: SOFT, align: c.cv }),
    staleNode(c, 11), Spacer());
}

function forecastView(c) {
  const days = daily(c.v);
  const withHead = c.ah >= 110;
  const hs = fc(c.ah * 0.14, 18, 40);
  const head = withHead ? hs * 1.6 : 0;
  const size = fc(Math.min((c.ah - head) / 5 / 1.75, c.aw / 14), 11, 26);
  const cnt = fc(Math.floor((c.ah - head) / (size * 1.75)), 1, 5);
  const list = days.slice(0, cnt);
  return frame(c, Spacer(),
    withHead ? headerRow(c, hs) : null,
    list.length ? VStack({ spacing: size * 0.55, alignment: "leading", width: c.aw }, list.map((d) => dayRow(d, size)))
      : Text({ text: DASH, size: 18, color: SOFT, align: c.cv }),
    staleNode(c, 11), Spacer());
}

export default defineWidget({
  sources: (s) => ({ w: http(forecastURL(s), { every: 900 }) }),

  render(ctx) {
    const s = ctx.settings || {};
    const city = validCity(s.city);
    const res = ctx.data && ctx.data.w;
    const v = res && res.value && typeof res.value === "object" ? res.value : null;
    const cur = v && v.current && typeof v.current === "object" ? v.current : null;
    const isDay = cur && cur.is_day === 0 ? false : true;
    const info = cur ? wmo(cur.weather_code, isDay) : { text: DASH, symbol: "cloud.fill" };
    const temp = cur ? deg(cur.temperature_2m) : DASH;
    const d0 = daily(v)[0];
    const hiLo = d0 ? "↓" + deg(d0.min) + " ↑" + deg(d0.max) : DASH;
    const stale = !!(res && res.stale);
    const pad = 14;
    const al = alignInfo(ctx);
    const sv = al.mode === "auto" ? "leading" : al.v; // выравнивание стеков

    const w = ctx.size.width, h = ctx.size.height;
    const aw = Math.max(60, w - pad * 2), ah = Math.max(60, h - pad * 2);
    const style = STYLES.indexOf(s.style) >= 0 ? s.style : "default";
    if (style !== "default") {
      const c = { city, info, temp, hiLo, stale, v, w, h, aw, ah, al, cv: al.mode === "auto" ? "center" : al.v };
      if (style === "compact") return compactView(c);
      if (style === "big") return bigView(c);
      if (style === "hourly") return hourlyView(c);
      return forecastView(c);
    }
    const wide = aw >= 300 && aw >= ah * 1.5;
    const small = ah < 110 && aw < 220;
    const f = Math.max(0.85, Math.min(wide ? Math.min(aw / 420, ah / 150) : aw / 200, ah / 200, 2.4));
    const tall = !wide && ah >= 260 && aw >= 230;
    const tsize = wide ? Math.min(46 * f, ah * 0.36) : Math.min(46 * f, ah * (tall ? 0.18 : 0.34));
    const iconNode = wide ? null : Image({ systemName: info.symbol, size: Math.min(30 * f, ah * (tall ? 0.14 : 0.26)), color: symbolColor(info.symbol) });
    const isz = wide ? 0 : Math.min(30 * f, ah * (tall ? 0.14 : 0.26));
    const tw = wide ? aw * 0.38 : al.mode === "center" ? aw : Math.max(40, aw - isz - 16);
    const th = wide ? ah * 0.42 : ah * (tall ? 0.2 : small ? 0.5 : 0.34);
    const titleNode = VStack({ spacing: 0, alignment: sv },
      Text(T({ text: city.name, size: (aw < 160 ? 12 : 14) * f, weight: "semibold", color: WHITE, align: sv, lineLimit: 1 }, tw, th * 0.3)),
      Text(T({ text: temp, size: tsize, weight: "light", color: WHITE, align: sv, lineLimit: 1 }, tw, th * 0.7)));
    // auto/left: название слева, иконка справа; right: зеркально; center: колонкой по центру.
    let header;
    if (al.mode === "center") {
      header = VStack({ spacing: 2, alignment: "center" }, iconNode, titleNode);
    } else if (al.right) {
      header = HStack({ spacing: 8, alignment: "top" }, Spacer(), iconNode, titleNode);
    } else {
      header = HStack({ spacing: 8, alignment: "top" }, titleNode, Spacer(), iconNode);
    }

    const rows = [header];
    if (wide) {
      const cond = [Image({ systemName: info.symbol, size: 18 * f, color: symbolColor(info.symbol) }),
        Text({ text: info.text, size: 14 * f, weight: "medium", color: WHITE, lineLimit: 1 })];
      rows.push(HStack({ spacing: 6 }, ...(al.right ? cond.reverse() : cond)));
      rows.push(Text(T({ text: hiLo, size: 13 * f, color: SOFT, align: sv, lineLimit: 1 }, aw * 0.38, ah * 0.1)));
    } else if (!small) {
      rows.push(Text(T({ text: info.text, size: 14 * f, weight: "medium", color: WHITE, align: sv, lineLimit: 1 }, aw, ah * 0.1)));
      rows.push(Text(T({ text: hiLo, size: 13 * f, color: SOFT, align: sv, lineLimit: 1 }, aw, ah * 0.08)));
    }
    let right = null;
    if (wide) {
      const rw = Math.floor(aw * 0.58);
      const hf = Math.min(f, 1.5);
      const n = Math.max(3, Math.min(8, Math.floor(rw / (46 * hf))));
      const hrs = hourly(v, n);
      const cellH = 13 * hf * 2 + 4 + 13 * hf + 14 + 12;
      const rr = [HStack({ spacing: 0, alignment: "top" },
        hrs.length ? hrs.map((hh) => hourCell(hh, 13 * hf, Math.floor(rw / n))) : Text({ text: DASH, size: 14, color: SOFT }))];
      const rowH = 13 * hf + 9;
      const dn = Math.max(0, Math.min(5, Math.floor((ah - cellH - 12) / rowH)));
      if (dn > 0) {
        rr.push(VStack({ spacing: 5 * hf, alignment: "leading", width: rw },
          daily(v).slice(0, dn).map((d) => dayRow(d, 13 * hf))));
      }
      right = VStack({ spacing: 8, alignment: "leading", width: rw }, Spacer({ minLength: 0 }), ...rr, Spacer({ minLength: 0 }));
    } else if (tall) {
      const hf = Math.min(f, 1.6);
      const n = Math.max(4, Math.min(10, Math.floor(aw / (46 * hf))));
      const hrs = hourly(v, n);
      rows.push(Spacer({ minLength: 4 }));
      rows.push(HStack({ spacing: 0, alignment: "top" },
        hrs.length ? hrs.map((hh) => hourCell(hh, 13 * hf, Math.floor(aw / n))) : Text({ text: DASH, size: 14, color: SOFT })));
      const rowH = 13 * hf + 11;
      const hourH = 13 * hf * 3 + 30;
      const used = tsize + 14 * f * 3 + 40 + hourH;
      const dayCount = Math.max(0, Math.min(5, Math.floor((ah - used) / rowH)));
      if (dayCount > 0) {
        rows.push(VStack({ spacing: 6 * hf, alignment: "leading" },
          daily(v).slice(0, dayCount).map((d) => dayRow(d, 13 * hf))));
      }
    }
    rows.push(Spacer());
    if (stale) rows.push(Text({ text: "Updated earlier", size: 11, color: SOFT, align: sv, lineLimit: 1 }));

    const left = VStack({ spacing: small ? 2 : 4 * f, alignment: sv, width: wide ? Math.floor(aw * 0.38) : undefined }, rows);
    // wide: left/auto — текущая сводка слева, прогноз справа; right — зеркально (прогноз слева, сводка справа);
    // center — сводка и прогноз единым блоком по центру.
    if (wide) {
      if (al.right) return HStack({ spacing: 12, alignment: "center", padding: pad, width: w, height: h }, right, Spacer({ minLength: 0 }), left);
      if (al.mode === "center") return HStack({ spacing: 12, alignment: "center", padding: pad, width: w, height: h }, Spacer({ minLength: 0 }), left, right, Spacer({ minLength: 0 }));
      return HStack({ spacing: 12, alignment: "center", padding: pad, width: w, height: h }, left, Spacer({ minLength: 0 }), right);
    }
    return VStack({ spacing: small ? 2 : 4 * f, alignment: sv, padding: pad, width: w, height: h }, rows);
  },
});
