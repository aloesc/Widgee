import { defineWidget, VStack, HStack, ZStack, Spacer, Text, LinearBar, timer } from "widgee";

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
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function firstDay(st) { return st && st.weekStart === "Sunday" ? 0 : 1; }
function letters(first) { return first === 1 ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]; }
const isWeekend = (first, col) => { const d = (first + col) % 7; return d === 0 || d === 6; };

// Ячейка: сегодня — акцентный кружок с белой цифрой.
function cell(text, cw, ch, d, fs, today, weekend) {
  return ZStack({ alignment: "center", width: cw, height: ch },
    today ? LinearBar({ value: 1, color: "accent", width: d, height: d }) : null,
    text === "" ? null : Text({ text, size: fs, weight: today ? "bold" : "regular", color: today ? "#FFFFFF" : weekend ? "secondary" : "primary", align: "center", lineLimit: 1 }));
}

function monthView(now, st, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const first = firstDay(st);
  const y = now.getFullYear(), m = now.getMonth(), today = now.getDate();
  const dim = new Date(y, m + 1, 0).getDate();
  const off = (new Date(y, m, 1).getDay() - first + 7) % 7;
  const rows = Math.ceil((off + dim) / 7);
  const mname = MONTHS[m];
  // Название месяца и год получают явную ширину: иначе Text рядом с Spacer в HStack обрезается («Nove…»).
  const ts = clamp(Math.min(ah * 0.1, aw / ((mname.length + 4) * 0.62 + 1)), 10, 34);
  const tH = Math.max(16, ah * 0.12);
  const ch = clamp((ah - tH - 6) / (rows + 0.6), 10, 80), cw = aw / 7;
  const d = Math.min(cw, ch) * 0.9, fs = clamp(Math.min(cw * 0.5, ch * 0.5), 7, 34);
  const names = letters(first);
  const head = HStack({ spacing: 0 }, ...names.map((n, i) => cell(n, cw, ch * 0.6, 0, fs * 0.8, false, true)));
  const weeks = [];
  for (let r = 0; r < rows; r++) {
    const cs = [];
    for (let c = 0; c < 7; c++) {
      const day = r * 7 + c - off + 1;
      const ok = day >= 1 && day <= dim;
      cs.push(cell(ok ? String(day) : "", cw, ch, d, fs, ok && day === today, isWeekend(first, c)));
    }
    weeks.push(HStack({ spacing: 0 }, ...cs));
  }
  const title = split(al, 6,
    Text(T({ text: mname, size: ts, weight: "semibold", color: "accent", lineLimit: 1, align: "leading", width: Math.ceil(ts * 0.62 * mname.length + 8) }, aw * 0.6, tH)),
    Text(T({ text: String(y), size: ts, color: "secondary", lineLimit: 1, width: Math.ceil(ts * 0.62 * 4 + 8), align: "trailing" }, aw * 0.32, tH)));
  return VStack({ spacing: 0, alignment: "center", padding: PAD, width: w, height: h }, Spacer({ minLength: 0 }), title, head, ...weeks, Spacer({ minLength: 0 }));
}

function weekView(now, st, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const first = firstDay(st);
  const col = (now.getDay() - first + 7) % 7;
  const cw = aw / 7;
  const showTitle = ah >= 80;
  const f = clamp(Math.min(cw / 34, ah / (showTitle ? 96 : 66)), 0.6, 3.5);
  const names = letters(first);
  const cells = [];
  for (let i = 0; i < 7; i++) {
    const dt = new Date(now.getFullYear(), now.getMonth(), now.getDate() - col + i);
    const today = i === col;
    cells.push(VStack({ spacing: 3 * f, alignment: "center", width: cw },
      Text({ text: names[i], size: 11 * f, color: "secondary", align: "center", lineLimit: 1 }),
      cell(String(dt.getDate()), 30 * f, 30 * f, 28 * f, 15 * f, today, isWeekend(first, i))));
  }
  const tbh = Math.min(ah * 0.2, 14 * f * 1.6);
  const title = hrow(al.lead, 6 * f,
    Text(T({ text: MONTHS[now.getMonth()], size: 14 * f, weight: "semibold", color: "accent", align: "leading", lineLimit: 1 }, aw * 0.55, tbh)),
    Text(T({ text: String(now.getFullYear()), size: 14 * f, color: "secondary", align: "leading", lineLimit: 1 }, aw * 0.3, tbh)));
  return page(w, h, "center", 6 * f, showTitle ? title : null, HStack({ spacing: 0 }, ...cells));
}

function dateView(now, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const wd = WEEKDAYS[now.getDay()], my = MONTHS[now.getMonth()] + " " + now.getFullYear(), dn = String(now.getDate());
  if (aw >= ah * 1.8) {
    const f = clamp(Math.min(aw / 260, ah / 90), 0.7, 3);
    const side = al.mode === "right" ? "trailing" : al.mode === "center" ? "center" : "leading";
    const bigW = aw * 0.4, colW2 = aw - bigW - 16, ih = hts(ah, 2 * f, 0.6, 0.4);
    const big = Text(T({ text: dn, size: 80 * f, weight: "semibold", color: "accent", monospacedDigit: true, align: "center", lineLimit: 1 }, bigW, ah));
    const info = VStack({ spacing: 2 * f, alignment: side, width: colW2 },
      Text(T({ text: wd, size: fitSize(wd, 24 * f, colW2), weight: "semibold", align: side, lineLimit: 1 }, colW2, ih[0])),
      Text(T({ text: my, size: fitSize(my, 16 * f, colW2), color: "secondary", align: side, lineLimit: 1 }, colW2, ih[1])));
    return HStack({ spacing: 16, alignment: "center", padding: PAD, width: w, height: h },
      ...(al.mode === "right" ? [Spacer(), info, big] : al.mode === "left" ? [big, info, Spacer()] : [Spacer(), big, info, Spacer()]));
  }
  const f = clamp(Math.min(aw / 110, ah / 135), 0.7, 3.5);
  const nh = hts(ah, 2 * f, 0.2, 0.58, 0.22);
  return page(w, h, al.v, 2 * f,
    Text(T({ text: wd, size: fitSize(wd, 18 * f, aw), weight: "semibold", color: "accent", align: al.v, lineLimit: 1 }, aw, nh[0])),
    Text(T({ text: dn, size: fitSize(dn, 80 * f, aw), weight: "semibold", monospacedDigit: true, align: al.v, lineLimit: 1 }, aw, nh[1])),
    Text(T({ text: my, size: fitSize(my, 15 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }, aw, nh[2])));
}

export default defineWidget({
  sources: { now: timer(60) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const t = ctx.data && ctx.data.now && num(ctx.data.now.now) ? ctx.data.now.now : Date.now();
    const now = new Date(t);
    if (st.style === "compact") return weekView(now, st, al, w, h);
    if (st.style === "date") return dateView(now, al, w, h);
    return monthView(now, st, al, w, h);
  },
});
