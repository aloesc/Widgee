import { defineWidget, VStack, HStack, Spacer, Text, DigitalClock, timer } from "widgee";

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

function cityLabel(label, tz) {
  if (typeof label === "string" && label.trim() !== "") return label.trim();
  const last = String(tz).split("/").pop() || tz;
  return last.replace(/_/g, " ");
}
function ymd(date, tz) {
  const o = { year: "numeric", month: "2-digit", day: "2-digit" };
  if (tz) o.timeZone = tz;
  const m = /(\d{4})-(\d{2})-(\d{2})/.exec(date.toLocaleDateString("en-CA", o));
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3]) : null;
}
function dayHint(now, tz) {
  try {
    const a = ymd(new Date(now), tz), b = ymd(new Date(now), "");
    if (a === null || b === null) return "";
    const d = Math.round((a - b) / 86400000);
    return d === 0 ? "Today" : d === 1 ? "Tomorrow" : d === -1 ? "Yesterday" : "";
  } catch (e) { return ""; }
}
function cities(st, now) {
  const out = [];
  const add = (i) => {
    const tz = typeof st["tz" + i] === "string" ? st["tz" + i].trim() : "";
    if (tz !== "") out.push({ tz, label: cityLabel(st["label" + i], tz), hint: dayHint(now, tz) });
  };
  add(1); add(2);
  if (st.showThird !== false) add(3);
  if (st.showFourth === true) add(4);
  if (out.length === 0) out.push({ tz: undefined, label: "Local", hint: "" });
  return out.slice(0, 4);
}

function listView(list, st, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const n = list.length, rh = ah / n;
  const chars = (st.hour12 === true ? 8 : 5) + (st.showSeconds === true ? 3 : 0);
  const maxLen = Math.max(...list.map((c) => c.label.length));
  const ls = clamp(Math.min(rh * 0.3, (aw * 0.42) / (maxLen * 0.58)), 9, 28);
  const labelW = Math.min(aw * 0.45, maxLen * 0.58 * ls);
  const ts = clamp(Math.min(rh * 0.62, (aw - labelW - 10) / (chars * 0.6)), 10, 70);
  const hint = rh >= 42;
  const rowH = Math.max(12, (ah - 2 * (n - 1)) / n), boxLW = aw * 0.4, boxTW = Math.max(30, aw - boxLW - 24);
  const sideL = al.mode === "auto" ? "leading" : al.v, sideT = al.mode === "auto" ? "trailing" : al.v;
  const rows = list.map((c) => split(al, 10,
    VStack({ spacing: 1, alignment: "leading" },
      Text(T({ text: c.label, size: ls, weight: "medium", align: sideL, lineLimit: 1 }, boxLW, hint && c.hint !== "" ? rowH * 0.58 : rowH * 0.9)),
      hint && c.hint !== "" ? Text(T({ text: c.hint, size: ls * 0.75, color: "secondary", align: sideL, lineLimit: 1 }, boxLW, rowH * 0.32)) : null),
    DigitalClock(T({ timeZone: c.tz, hour12: st.hour12 === true, showSeconds: st.showSeconds === true, size: ts, weight: "medium", align: sideT }, boxTW, rowH * 0.9))));
  return VStack({ spacing: 0, alignment: "center", padding: PAD, width: w, height: h }, Spacer({ minLength: 0 }), ...rows.flatMap((r, i) => (i ? [Spacer({ minLength: 2 }), r] : [r])), Spacer({ minLength: 0 }));
}

function columnsView(list, st, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const n = list.length, cw = aw / n;
  const chars = (st.hour12 === true ? 8 : 5) + (st.showSeconds === true ? 3 : 0);
  const ts = clamp(Math.min(cw / (chars * 0.62), ah * 0.35), 10, 80);
  const side = al.mode === "auto" ? "center" : al.v;
  const showHint = (c) => ah >= 90 && c.hint !== "";
  const cols = list.map((c) => { const ch = hts(ah, 4, 0.22, 0.56, showHint(c) ? 0.16 : 0);
    return VStack({ spacing: 4, alignment: side, width: cw },
    Spacer({ minLength: 0 }),
    Text(T({ text: c.label, size: fitSize(c.label, clamp(ts * 0.45, 10, 30), cw - 4), weight: "medium", color: "secondary", align: side, lineLimit: 1 }, cw - 4, ch[0])),
    DigitalClock(T({ timeZone: c.tz, hour12: st.hour12 === true, showSeconds: st.showSeconds === true, size: ts, weight: "medium", align: side }, cw - 4, ch[1])),
    showHint(c) ? Text(T({ text: c.hint, size: clamp(ts * 0.35, 9, 20), color: "secondary", align: side, lineLimit: 1 }, cw - 4, ch[2])) : null,
    Spacer({ minLength: 0 })); });
  return HStack({ spacing: 0, alignment: "center", padding: PAD, width: w, height: h }, ...cols);
}

export default defineWidget({
  sources: { now: timer(60) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const t = ctx.data && ctx.data.now && num(ctx.data.now.now) ? ctx.data.now.now : Date.now();
    const list = cities(st, t);
    return st.layout === "columns" ? columnsView(list, st, al, w, h) : listView(list, st, al, w, h);
  },
});
