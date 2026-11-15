import { defineWidget, VStack, HStack, Spacer, Text, LinearBar, Ring, timer } from "widgee";

const PAD = 14;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const num = (v) => typeof v === "number" && isFinite(v);
const clamp01 = (v) => (num(v) ? Math.max(0, Math.min(1, v)) : 0);
const HEX = /^#[0-9a-fA-F]{6}$/;
const DASH = "—";
// Текст рисуется fit-кеглем в коробке w x h (pt). Ручной «Text size» (ctx.theme.textScale) применяет хост.
const T = (o, w, h) => (w > 0 && h > 0 ? { ...o, fit: true, width: Math.floor(w), height: Math.floor(h) } : o);
// Высоты коробок: total делится на элементы с весами wt, между ними spacing sp.
const hts = (total, sp, ...wt) => { const av = Math.max(8, total - sp * (wt.length - 1)), s = wt.reduce((a, b) => a + b, 0); return wt.map((x) => av * x / s); };

// Выравнивание содержимого (ctx.theme.alignment): auto | left | center | right.
function alignInfo(ctx) {
  const a = ctx && ctx.theme ? ctx.theme.alignment : "auto";
  const mode = a === "left" || a === "center" || a === "right" ? a : "auto";
  const v = mode === "left" ? "leading" : mode === "right" ? "trailing" : "center";
  // lead: для виджетов, у которых собственная раскладка (auto) прижата влево.
  return { mode, v, lead: mode === "auto" ? "leading" : v };
}
// Размер шрифта, при котором текст (грубая оценка 0.6 em на символ) помещается в maxW.
const fitSize = (text, size, maxW) => Math.max(8, Math.min(size, maxW / (Math.max(1, String(text).length) * 0.6)));
// Ряд, прижатый к краю: side = leading | trailing | center.
function hrow(side, spacing, ...kids) {
  if (side === "leading") return HStack({ spacing }, ...kids, Spacer());
  if (side === "trailing") return HStack({ spacing }, Spacer(), ...kids);
  return HStack({ spacing }, Spacer(), ...kids, Spacer());
}
// Два элемента: auto = по краям; left/center/right = вместе у края/по центру.
function split(al, spacing, a, b) {
  return al.mode === "auto" ? HStack({ spacing }, a, Spacer(), b) : hrow(al.v, spacing, a, b);
}
function page(w, h, side, spacing, ...kids) {
  return VStack({ spacing, alignment: side, padding: PAD, width: w, height: h }, Spacer({ minLength: 0 }), ...kids, Spacer({ minLength: 0 }));
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function items(now, st) {
  const y = now.getFullYear(), m = now.getMonth(), d = now.getDate();
  const dayFrac = clamp01((now - new Date(y, m, d)) / 86400000);
  const first = st.weekStart === "Sunday" ? 0 : 1;
  const col = (now.getDay() - first + 7) % 7;
  const dim = new Date(y, m + 1, 0).getDate();
  const year = clamp01((now - new Date(y, 0, 1)) / (new Date(y + 1, 0, 1) - new Date(y, 0, 1)));
  const acc = st.accentOnly === true;
  const all = [
    { on: st.showDay !== false, label: "Today", value: dayFrac, color: "accent" },
    { on: st.showWeek !== false, label: "This week", value: (col + dayFrac) / 7, color: acc ? "accent" : "#30D158" },
    { on: st.showMonth !== false, label: MONTHS[m], value: (d - 1 + dayFrac) / dim, color: acc ? "accent" : "#FF9F0A" },
    { on: st.showYear !== false, label: String(y), value: year, color: acc ? "accent" : "#BF5AF2" },
  ].filter((i) => i.on);
  return all.length ? all : [{ label: "Today", value: dayFrac, color: "accent" }];
}
const pct = (v) => Math.floor(clamp01(v) * 100) + "%";

function barsView(list, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const n = list.length;
  const f = clamp(Math.min(aw / 200, ah / (n * 36)), 0.8, 2.6);
  const lh = Math.max(10, (ah - 11 * f * (n - 1)) / n - 11 * f);
  const rows = list.map((it) => VStack({ spacing: 4 * f, alignment: al.lead },
    split(al, 6 * f,
      Text(T({ text: it.label, size: 13 * f, color: "secondary", align: "leading", lineLimit: 1 }, aw * 0.55, lh)),
      Text(T({ text: pct(it.value), size: 14 * f, weight: "semibold", monospacedDigit: true, align: "trailing", lineLimit: 1 }, aw * 0.35, lh))),
    LinearBar({ value: clamp01(it.value), color: it.color, height: 7 * f })));
  return page(w, h, al.lead, 11 * f, ...rows);
}

function ringsView(list, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const n = list.length, gap = 10;
  let best = null;
  for (let c = 1; c <= n; c++) {
    const r = Math.ceil(n / c);
    const size = Math.min((aw - gap * (c - 1)) / c, (ah - r * 22 - gap * (r - 1)) / r);
    if (!best || size > best.size) best = { c, r, size };
  }
  const size = clamp(best.size, 30, 300);
  const cell = (it) => VStack({ spacing: 4, alignment: "center", width: size },
    Ring({ value: clamp01(it.value), color: it.color, size },
      Text(T({ text: pct(it.value), size: size / 4, weight: "semibold", monospacedDigit: true, align: "center", lineLimit: 1 }, size * 0.62, size * 0.3))),
    Text(T({ text: it.label, size: fitSize(it.label, clamp(size * 0.15, 10, 24), size + 8), color: "secondary", align: "center", lineLimit: 1 }, size + 8, 20)));
  const grid = [];
  for (let r = 0; r < best.r; r++) grid.push(hrow(al.v, gap, ...list.slice(r * best.c, (r + 1) * best.c).map(cell)));
  return page(w, h, al.v, gap, ...grid);
}

export default defineWidget({
  sources: { now: timer(60) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const t = ctx.data && ctx.data.now && num(ctx.data.now.now) ? ctx.data.now.now : Date.now();
    const list = items(new Date(t), st);
    const w = ctx.size.width, h = ctx.size.height;
    return st.style === "rings" ? ringsView(list, al, w, h) : barsView(list, al, w, h);
  },
});
