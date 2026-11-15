import { defineWidget, VStack, HStack, Spacer, Text, Image, LinearBar, Ring, system } from "widgee";

const PAD = 14;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const num = (v) => typeof v === "number" && isFinite(v);
const clamp01 = (v) => (num(v) ? Math.max(0, Math.min(1, v)) : 0);
const HEX = /^#[0-9a-fA-F]{6}$/;
const DASH = "—";
// Auto-режим (ctx.theme.textScale == null): текст рисуется fit-кеглем в коробке w x h (pt).
let AUTO = false;
const T = (o, w, h) => (AUTO && w > 0 && h > 0 ? { ...o, fit: true, width: Math.floor(w), height: Math.floor(h) } : o);
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

function gb(n) {
  if (n >= 1e12) return { n: (n / 1e12).toFixed(2), u: "TB" };
  return { n: n >= 1e11 ? String(Math.round(n / 1e9)) : (n / 1e9).toFixed(1), u: "GB" };
}
const txt = (n) => { const g = gb(n); return g.n + " " + g.u; };

function pickColor(st, fill) {
  if (st.colorMode === "Accent") return "accent";
  if (st.colorMode === "Custom" && typeof st.color === "string" && HEX.test(st.color)) return st.color;
  return fill >= 0.95 ? "#FF453A" : fill >= 0.85 ? "#FF9F0A" : "#0A84FF";
}

function ringView(d, al, w, h, c, free) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const main = gb(free ? d.free : d.used), word = free ? "free" : "used";
  const mk = (r) => Ring({ value: d.fill, color: c, size: r },
    VStack({ spacing: 0, alignment: "center" },
      Text(T({ text: main.n, size: fitSize(main.n, r / 3.6, r * 0.62), weight: "semibold", monospacedDigit: true, align: "center", lineLimit: 1 }, r * 0.62, r * 0.36)),
      Text(T({ text: main.u + " " + word, size: clamp(r / 9, 8, 30), color: "secondary", align: "center", lineLimit: 1 }, r * 0.62, r * 0.14))));
  const of = "of " + txt(d.total);
  if (aw >= ah * 1.7) {
    const r = clamp(ah, 40, 300), colW = Math.max(40, aw - r - 16);
    const big = fitSize("100 GB", clamp(r * 0.32, 14, 100), colW);
    const side = al.mode === "right" ? "trailing" : al.mode === "center" ? "center" : "leading";
    const info = VStack({ spacing: 3, alignment: side, width: colW },
      Text(T({ text: main.n + " " + main.u, size: big, weight: "semibold", monospacedDigit: true, align: side, lineLimit: 1 }, colW, hts(ah, 3, 0.65, 0.35)[0])),
      Text(T({ text: (free ? "free " : "used ") + of, size: fitSize("used of 500 GB", clamp(big * 0.4, 10, 36), colW), color: "secondary", align: side, lineLimit: 1 }, colW, hts(ah, 3, 0.65, 0.35)[1])));
    const kids = al.mode === "right" ? [info, mk(r)] : [mk(r), info];
    return HStack({ spacing: 16, alignment: "center", padding: PAD, width: w, height: h }, ...kids);
  }
  const lab = ah >= 110;
  const r = clamp(Math.min(aw, ah - (lab ? 24 : 0)), 36, 300);
  return page(w, h, al.v, 6, mk(r),
    lab ? Text(T({ text: of, size: fitSize(of, clamp(r * 0.1, 11, 22), aw), color: "secondary", align: al.v, lineLimit: 1 }, aw, Math.max(14, ah - r - 12))) : null);
}

function barView(d, al, w, h, c) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = clamp(Math.min(aw / 200, ah / 70), 0.8, 3.2);
  const head = split(al, 6 * f,
    HStack({ spacing: 5 * f }, Image({ systemName: "internaldrive", size: 16 * f, color: c }),
      Text({ text: "Storage", size: 14 * f, color: "secondary", lineLimit: 1 })),
    Text(T({ text: Math.round(d.fill * 100) + "%", size: 22 * f, weight: "semibold", monospacedDigit: true, align: "trailing", lineLimit: 1 }, aw * 0.4, ah * 0.32)));
  const foot = split(al, 8 * f,
    Text(T({ text: txt(d.used) + " used", size: 12 * f, monospacedDigit: true, align: "leading", lineLimit: 1 }, aw * 0.46, ah * 0.16)),
    Text(T({ text: txt(d.free) + " free", size: 12 * f, color: "secondary", monospacedDigit: true, align: "trailing", lineLimit: 1 }, aw * 0.46, ah * 0.16)));
  return page(w, h, al.lead, 7 * f, head, LinearBar({ value: d.fill, color: c, height: 8 * f }), foot);
}

function detailView(d, al, w, h, c) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const wide = aw >= ah * 1.7;
  const f = wide ? clamp(Math.min((aw - ah) / 150, ah / 100), 0.8, 3) : clamp(Math.min(aw / 150, ah / 200), 0.7, 2.5);
  const kv = (l, v, col) => split(al, 6 * f, Text({ text: l, size: 12 * f, color: "secondary", lineLimit: 1 }),
    Text({ text: v, size: 13 * f, weight: "semibold", color: col, monospacedDigit: true, lineLimit: 1 }));
  const rows = (width) => VStack({ spacing: 5 * f, alignment: al.lead, width },
    hrow(al.lead, 5 * f, Image({ systemName: "internaldrive", size: 15 * f, color: c }), Text({ text: "Storage", size: 14 * f, weight: "semibold", lineLimit: 1 })),
    kv("Used", txt(d.used), "primary"), kv("Free", txt(d.free), "primary"), kv("Total", txt(d.total), "secondary"));
  const mk = (r) => Ring({ value: d.fill, color: c, size: r },
    Text(T({ text: Math.round(d.fill * 100) + "%", size: r / 4, weight: "semibold", monospacedDigit: true, align: "center", lineLimit: 1 }, r * 0.62, r * 0.3)));
  if (wide) {
    const r = clamp(ah, 40, 300), colW = Math.max(60, aw - r - 20);
    const kids = al.mode === "right" ? [rows(colW), mk(r)] : [mk(r), rows(colW)];
    return HStack({ spacing: 20, alignment: "center", padding: PAD, width: w, height: h }, ...kids);
  }
  const r = clamp(Math.min(aw, ah - 88 * f), 36, 240);
  return page(w, h, al.v, 8 * f, mk(r), rows(aw));
}

export default defineWidget({
  sources: { disk: system("disk", { interval: 30 }) },
  render(ctx) {
    const st = ctx.settings || {};
    AUTO = !!ctx.theme && ctx.theme.textScale == null;
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const raw = ctx.data ? ctx.data.disk : null;
    if (!raw || !num(raw.total) || raw.total <= 0 || !num(raw.free)) {
      const aw = w - PAD * 2, ah = h - PAD * 2, f = clamp(Math.min(aw / 150, ah / 70), 0.8, 3);
      return page(w, h, al.v, 4 * f, Image({ systemName: "internaldrive", size: 28 * f, color: "secondary" }),
        Text(T({ text: "Storage", size: 15 * f, weight: "semibold", align: al.v, lineLimit: 1 }, aw, ah * 0.25)),
        Text(T({ text: "Reading disk…", size: fitSize("Reading disk…", 11 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }, aw, ah * 0.15)));
    }
    const free = clamp(raw.free, 0, raw.total);
    const d = { total: raw.total, free, used: raw.total - free, fill: clamp01(1 - free / raw.total) };
    const c = pickColor(st, d.fill);
    if (st.style === "bar") return barView(d, al, w, h, c);
    if (st.style === "detailed") return detailView(d, al, w, h, c);
    return ringView(d, al, w, h, c, st.show === "Free");
  },
});
