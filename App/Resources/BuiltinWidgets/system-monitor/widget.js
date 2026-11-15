import { defineWidget, VStack, HStack, Spacer, Text, Image, LinearBar, Ring, Gauge, SegmentedBar, Sparkline, system } from "widgee";

const HISTORY = 90;
const hist = { cpu: [], ram: [], down: [] };
function push(arr, v) {
  arr.push(v);
  while (arr.length > HISTORY) arr.shift();
}

const DASH = "—";
const pct = (v) => (typeof v === "number" && isFinite(v) ? Math.round(v * 100) + " %" : DASH);
const clamp01 = (v) => (typeof v === "number" && isFinite(v) ? Math.max(0, Math.min(1, v)) : 0);

function bytes(n) {
  if (typeof n !== "number" || !isFinite(n)) return DASH;
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + u[i];
}

function collect(d) {
  d = d || {};
  const cpu = d.cpu && typeof d.cpu.total === "number" ? d.cpu.total : null;
  const ram = d.ram && d.ram.total > 0 ? d.ram.used / d.ram.total : null;
  const disk = d.disk && d.disk.total > 0 ? 1 - d.disk.free / d.disk.total : null;
  const net = d.network || null;
  const bat = d.battery || null;
  return { cpu, ram, disk, net, bat, d };
}

// Цвета метрик: colorMode = Per metric | Single color | By fill level | Custom per metric.
const NEUTRAL = "#8E8E93";
const HEX = /^#[0-9a-fA-F]{6}$/;
const DEFAULT_COLORS = { cpu: "#0A84FF", ram: "#30D158", disk: "#FF9F0A", net: "#FF9F0A", battery: "#30D158" };
// Шкала заполнения: зелёный -> жёлтый (0.6) -> оранжевый (0.85) -> красный (1).
const LEVEL_STOPS = [[0, [48, 209, 88]], [0.6, [255, 214, 10]], [0.85, [255, 159, 10]], [1, [255, 69, 58]]];

function levelColor(v) {
  const t = clamp01(v);
  let i = 1;
  while (i < LEVEL_STOPS.length - 1 && t > LEVEL_STOPS[i][0]) i++;
  const a = LEVEL_STOPS[i - 1], b = LEVEL_STOPS[i];
  const k = (t - a[0]) / (b[0] - a[0]);
  const hx = (j) => Math.round(a[1][j] + (b[1][j] - a[1][j]) * k).toString(16).padStart(2, "0");
  return "#" + (hx(0) + hx(1) + hx(2)).toUpperCase();
}

// key: cpu|ram|disk|net|battery; fill: доля заполнения 0...1 (батарея: заряд, инвертируется) или null; base: цвет режима Per metric.
function metricColor(st, key, fill, base) {
  if (typeof fill !== "number" || !isFinite(fill)) return NEUTRAL;
  const mode = st && st.colorMode;
  if (mode === "Single color") return st.singleColor && HEX.test(st.singleColor) ? st.singleColor : DEFAULT_COLORS.cpu;
  if (mode === "By fill level") return levelColor(key === "battery" ? 1 - fill : fill);
  if (mode === "Custom per metric") {
    const c = st[key + "Color"];
    return typeof c === "string" && HEX.test(c) ? c : DEFAULT_COLORS[key];
  }
  return base;
}

// Доля сетевой загрузки: относительно пика истории (не меньше 1 МБ/с).
function netFill(m) {
  if (!m.net || typeof m.net.downBytesPerSec !== "number") return null;
  const peak = Math.max(1048576, ...hist.down);
  return clamp01(m.net.downBytesPerSec / peak);
}

function items(m, sc, w, h) {
  const list = [
    { key: "cpu", icon: "cpu", label: "CPU", value: m.cpu, text: pct(m.cpu), color: metricColor(m.st, "cpu", m.cpu, "accent") },
    { key: "ram", icon: "memorychip", label: "RAM", value: m.ram, text: pct(m.ram), color: metricColor(m.st, "ram", m.ram, "#30D158"),
      sub: m.d.ram ? bytes(m.d.ram.used) + " / " + bytes(m.d.ram.total) : DASH },
    { key: "disk", icon: "internaldrive", label: "Disk", value: m.disk, text: pct(m.disk), color: metricColor(m.st, "disk", m.disk, "#FF9F0A"),
      sub: m.d.disk ? bytes(m.d.disk.free) + " free" : DASH },
  ];
  if (h >= 230 || (w >= 380 && h >= 150)) {
    list.push({
      key: "battery",
      icon: m.bat && m.bat.isCharging ? "battery.100.bolt" : "battery.75",
      label: "Battery", value: m.bat ? m.bat.level : null, text: m.bat ? pct(m.bat.level) : DASH,
      color: metricColor(m.st, "battery", m.bat ? m.bat.level : null, m.bat && m.bat.level < 0.2 ? "#FF453A" : "#30D158"),
    });
  }
  return h < 190 && w < 260 ? list.slice(0, 2) : list;
}

function netLine(m, size) {
  const n = m.net;
  return HStack({ spacing: size * 0.8 },
    Image({ systemName: "arrow.down", size, color: "secondary" }),
    Text({ text: n ? bytes(n.downBytesPerSec) + "/s" : DASH, size, monospacedDigit: true, lineLimit: 1 }),
    Image({ systemName: "arrow.up", size, color: "secondary" }),
    Text({ text: n ? bytes(n.upBytesPerSec) + "/s" : DASH, size, monospacedDigit: true, lineLimit: 1 }));
}

// Выравнивание содержимого (ctx.theme.alignment): auto | left | center | right.
// Возвращает параметры раскладки; auto = собственная раскладка виджета.
function alignInfo(ctx) {
  const a = ctx && ctx.theme ? ctx.theme.alignment : "auto";
  const mode = a === "left" || a === "center" || a === "right" ? a : "auto";
  const v = mode === "left" ? "leading" : mode === "right" ? "trailing" : "center"; // VStack alignment / Text.align
  return { mode, v, left: mode === "left", right: mode === "right", centered: mode === "center" || mode === "auto" };
}

const PAD = 14;
const fclamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

function bars(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const showNet = h >= 150 && w >= 200;
  const n = list.length + (showNet ? 1 : 0);
  const f = fclamp(Math.min(ah / (n * 40), aw / 240), 0.85, 2.6);
  const out = [];
  list.forEach((it, i) => {
    if (i > 0) out.push(Spacer({ minLength: 4 }));
    out.push(VStack({ spacing: 3 * f, alignment: al.mode === "auto" ? "leading" : al.v },
      HStack({ spacing: 6 },
        Image({ systemName: it.icon, size: 12 * f, color: it.color }),
        Text({ text: it.label, size: 12 * f, color: "secondary", lineLimit: 1 }),
        al.mode === "auto" ? Spacer() : null,
        Text({ text: it.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
      LinearBar({ value: clamp01(it.value), color: it.color, height: 6 * f })));
  });
  if (showNet) { out.push(Spacer({ minLength: 4 })); out.push(netLine(m, 12 * f)); }
  return VStack({ spacing: 0, alignment: al.mode === "auto" ? "leading" : al.v, padding: PAD, width: w, height: h }, Spacer({ minLength: 0 }), ...out, Spacer({ minLength: 0 }));
}

function rings(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const showNet = h >= 260 && w >= 220;
  const netH = showNet ? 28 : 0;
  const gap = 12, n = list.length;
  let best = null;
  for (let c = 1; c <= n; c++) {
    const r = Math.ceil(n / c);
    const lab = 16;
    const size = Math.min((aw - gap * (c - 1)) / c, (ah - netH - r * (lab + 4) - gap * (r - 1)) / r);
    if (!best || size > best.size) best = { c, r, size };
  }
  const size = fclamp(best.size, 40, 360);
  const f = size / 70;
  const cell = (it) =>
    VStack({ spacing: 4, alignment: "center" },
      Ring({ value: clamp01(it.value), color: it.color, size },
        Text({ text: it.value === null || it.value === undefined ? DASH : Math.round(it.value * 100) + "", size: size / 3.4, weight: "semibold", monospacedDigit: true })),
      Text({ text: it.label, size: fclamp(11 * f, 11, 28), color: "secondary", lineLimit: 1 }));
  const grid = [];
  for (let r = 0; r < best.r; r++) {
    grid.push(HStack({ spacing: gap, alignment: "center" }, ...list.slice(r * best.c, (r + 1) * best.c).map(cell)));
  }
  return VStack({ spacing: gap, alignment: al.v, padding: PAD, width: w, height: h },
    Spacer(), ...grid, Spacer(), showNet ? netLine(m, 12) : null);
}

// Строка «подпись — значение»: auto = по краям; left/right/center = вместе у соответствующего края/центра.
function headRow(al, spacing, label, value) {
  if (al.mode === "auto") return HStack({ spacing }, label, Spacer(), value);
  if (al.left) return HStack({ spacing }, label, value, Spacer());
  if (al.right) return HStack({ spacing }, Spacer(), label, value);
  return HStack({ spacing }, Spacer(), label, value, Spacer());
}

function graphs(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const rows = [
    { label: "CPU", text: pct(m.cpu), values: hist.cpu, color: metricColor(m.st, "cpu", m.cpu, "accent") },
    { label: "RAM", text: pct(m.ram), values: hist.ram, color: metricColor(m.st, "ram", m.ram, "#30D158") },
  ];
  if (h >= 150) {
    rows.push({ label: "Network ↓", text: m.net ? bytes(m.net.downBytesPerSec) + "/s" : DASH, values: hist.down, color: metricColor(m.st, "net", netFill(m), "#FF9F0A") });
  }
  const extra = h >= 330 ? list.slice(2) : [];
  const f = fclamp(Math.min(aw / 260, ah / 220), 0.85, 2);
  const gap = 8 * f, head = 18 * f;
  const gh = fclamp((ah - extra.length * (head + 6 * f + gap) - rows.length * (head + gap)) / rows.length, 18, 260);
  return VStack({ spacing: gap, alignment: al.mode === "auto" ? "leading" : al.v, padding: PAD, width: w, height: h },
    ...rows.map((r) =>
      VStack({ spacing: 2, alignment: al.mode === "auto" ? "leading" : al.v },
        headRow(al, 6,
          Text({ text: r.label, size: 12 * f, color: "secondary", lineLimit: 1 }),
          Text({ text: r.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
        Sparkline({ values: r.values.length > 1 ? r.values : [0, 0], color: r.color, height: gh, fill: true }))),
    ...extra.map((it) =>
      VStack({ spacing: 3, alignment: al.mode === "auto" ? "leading" : al.v },
        headRow(al, 6, Text({ text: it.label, size: 12 * f, color: "secondary", lineLimit: 1 }),
          Text({ text: it.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
        LinearBar({ value: clamp01(it.value), color: it.color, height: 6 * f }))));
}

const sideAl = (al) => (al.mode === "auto" ? "leading" : al.v);

function gauges(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const showNet = h >= 260 && w >= 220;
  const netH = showNet ? 28 : 0;
  const gap = 12, n = list.length, lab = 16;
  let best = null;
  for (let c = 1; c <= n; c++) {
    const r = Math.ceil(n / c);
    const size = Math.min((aw - gap * (c - 1)) / c, ((ah - netH - gap * (r - 1)) / r - lab - 4) / 0.58);
    if (!best || size > best.size) best = { c, r, size };
  }
  const size = fclamp(best.size, 56, 360);
  const f = size / 90;
  const cell = (it) =>
    VStack({ spacing: 2, alignment: "center" },
      Gauge({ value: clamp01(it.value), color: it.color, size },
        Text({ text: it.value === null || it.value === undefined ? DASH : Math.round(it.value * 100) + "", size: size / 4, weight: "semibold", monospacedDigit: true })),
      Text({ text: it.label, size: fclamp(11 * f, 11, 26), color: "secondary", lineLimit: 1 }));
  const grid = [];
  for (let r = 0; r < best.r; r++) {
    grid.push(HStack({ spacing: gap, alignment: "center" }, ...list.slice(r * best.c, (r + 1) * best.c).map(cell)));
  }
  return VStack({ spacing: gap, alignment: al.v, padding: PAD, width: w, height: h },
    Spacer(), ...grid, Spacer(), showNet ? netLine(m, 12) : null);
}

function segmented(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const showNet = h >= 150 && w >= 200;
  const n = list.length + (showNet ? 1 : 0);
  const f = fclamp(Math.min(ah / (n * 40), aw / 240), 0.85, 2.6);
  const segs = Math.round(fclamp(aw / (9 * f), 8, 40));
  const out = [];
  list.forEach((it, i) => {
    if (i > 0) out.push(Spacer({ minLength: 4 }));
    out.push(VStack({ spacing: 3 * f, alignment: sideAl(al) },
      headRow(al, 6,
        HStack({ spacing: 6 }, Image({ systemName: it.icon, size: 12 * f, color: it.color }),
          Text({ text: it.label, size: 12 * f, color: "secondary", lineLimit: 1 })),
        Text({ text: it.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
      SegmentedBar({ value: clamp01(it.value), segments: segs, color: it.color, height: 8 * f, spacing: 2 })));
  });
  if (showNet) { out.push(Spacer({ minLength: 4 })); out.push(netLine(m, 12 * f)); }
  return VStack({ spacing: 0, alignment: sideAl(al), padding: PAD, width: w, height: h }, Spacer({ minLength: 0 }), ...out, Spacer({ minLength: 0 }));
}

function cores(list, m, w, h, al) {
  const pc = m.d && m.d.cpu && Array.isArray(m.d.cpu.perCore)
    ? m.d.cpu.perCore.filter((v) => typeof v === "number" && isFinite(v)) : [];
  if (pc.length === 0) return bars(list, m, w, h, al);
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = fclamp(Math.min(aw / 260, ah / 200), 0.85, 2);
  const head = 20 * f, gap = 4 * f;
  const rowMin = 11 * f + gap;
  const maxRows = Math.max(1, Math.floor((ah - head - 6) / rowMin));
  const cols = Math.max(1, Math.min(pc.length, Math.ceil(pc.length / maxRows), Math.floor(aw / (90 * f)) || 1));
  const rowsN = Math.ceil(pc.length / cols);
  const colGap = 10 * f;
  const cw = Math.floor((aw - colGap * (cols - 1)) / cols);
  const rowH = fclamp((ah - head - 6 - gap * (rowsN - 1)) / rowsN, 8, 28 * f);
  const cell = (v, i) =>
    HStack({ spacing: 5 * f, alignment: "center", width: cw },
      Text({ text: String(i + 1), size: Math.min(rowH, 11 * f), color: "secondary", monospacedDigit: true, lineLimit: 1, width: 16 * f, align: "trailing" }),
      LinearBar({ value: clamp01(v), color: metricColor(m.st, "cpu", v, "accent"), height: Math.max(4, rowH * 0.6) }));
  const grid = [];
  for (let r = 0; r < rowsN; r++) {
    const row = [];
    for (let c = 0; c < cols; c++) {
      const i = c * rowsN + r;
      if (i < pc.length) row.push(cell(pc[i], i));
    }
    grid.push(HStack({ spacing: colGap, alignment: "center" }, ...row));
  }
  return VStack({ spacing: gap, alignment: sideAl(al), padding: PAD, width: w, height: h },
    Spacer({ minLength: 0 }),
    headRow(al, 6, Text({ text: "CPU cores", size: 12 * f, color: "secondary", lineLimit: 1 }),
      Text({ text: pct(m.cpu), size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
    ...grid, Spacer({ minLength: 0 }));
}

function sparklines(list, m, w, h, al) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const rows = [
    { label: "CPU", text: pct(m.cpu), values: hist.cpu, color: metricColor(m.st, "cpu", m.cpu, "accent") },
    { label: "RAM", text: pct(m.ram), values: hist.ram, color: metricColor(m.st, "ram", m.ram, "#30D158") },
    { label: "Net ↓", text: m.net ? bytes(m.net.downBytesPerSec) + "/s" : DASH, values: hist.down, color: metricColor(m.st, "net", netFill(m), "#FF9F0A") },
  ];
  const n = h >= 120 ? 3 : 2;
  const shown = rows.slice(0, n);
  const f = fclamp(Math.min(aw / 260, ah / (n * 36)), 0.85, 2.2);
  const gap = 6 * f;
  const rh = fclamp((ah - gap * (n - 1)) / n, 18, 90 * f);
  const lw = 44 * f, vw = (aw > 300 ? 84 : 60) * f;
  const cells = shown.map((r) =>
    HStack({ spacing: 8 * f, alignment: "center" },
      Text({ text: r.label, size: 12 * f, color: "secondary", lineLimit: 1, width: lw, align: al.right ? "trailing" : "leading" }),
      Sparkline({ values: r.values.length > 1 ? r.values : [0, 0], color: r.color, height: rh, fill: true }),
      Text({ text: r.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1, width: vw, align: "trailing" })));
  const extra = h >= 210 ? list.filter((it) => it.key === "disk" || it.key === "battery") : [];
  return VStack({ spacing: gap, alignment: sideAl(al), padding: PAD, width: w, height: h },
    Spacer({ minLength: 0 }), ...cells,
    ...extra.map((it) => HStack({ spacing: 8 * f, alignment: "center" },
      Text({ text: it.label, size: 12 * f, color: "secondary", lineLimit: 1, width: lw }),
      LinearBar({ value: clamp01(it.value), color: it.color, height: 5 * f }),
      Text({ text: it.text, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1, width: vw, align: "trailing" }))),
    Spacer({ minLength: 0 }));
}

export default defineWidget({
  sources: {
    cpu: system("cpu", { interval: 2 }),
    ram: system("ram", { interval: 5 }),
    disk: system("disk", { interval: 30 }),
    network: system("network", { interval: 2 }),
    battery: system("battery", { interval: 30 }),
  },
  render(ctx) {
    const m = collect(ctx.data);
    m.st = ctx.settings || {};
    push(hist.cpu, m.cpu === null ? 0 : m.cpu);
    push(hist.ram, m.ram === null ? 0 : m.ram);
    push(hist.down, m.net ? m.net.downBytesPerSec : 0);
    const sc = ctx.size.sizeClass;
    const layout = ctx.settings && ctx.settings.layout;
    const w = ctx.size.width, h = ctx.size.height;
    const list = items(m, sc, w, h);
    const al = alignInfo(ctx);
    if (layout === "rings") return rings(list, m, w, h, al);
    if (layout === "graphs") return graphs(list, m, w, h, al);
    if (layout === "gauges") return gauges(list, m, w, h, al);
    if (layout === "segmented") return segmented(list, m, w, h, al);
    if (layout === "cores") return cores(list, m, w, h, al);
    if (layout === "sparklines") return sparklines(list, m, w, h, al);
    return bars(list, m, w, h, al);
  },
});
