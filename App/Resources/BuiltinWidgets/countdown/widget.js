import { defineWidget, VStack, HStack, Spacer, Text, Ring, timer } from "widgee";

const PAD = 14;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const num = (v) => typeof v === "number" && isFinite(v);
const clamp01 = (v) => (num(v) ? Math.max(0, Math.min(1, v)) : 0);
const HEX = /^#[0-9a-fA-F]{6}$/;
const DASH = "—";

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

const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY = 86400000;
function parseDate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || "").trim());
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  return isNaN(d.getTime()) ? null : d;
}
const plural = (n, one, many) => (n === 1 ? one : many);

function compute(now, st) {
  const target = parseDate(st.date);
  if (!target) return { big: DASH, unit: "Set a date in settings", sub: "", p: 0 };
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const dd = Math.round((target - today) / DAY);
  const ms = target - now;
  const hoursTotal = Math.max(0, Math.floor(ms / 3600000));
  const d = Math.floor(hoursTotal / 24), hr = hoursTotal % 24;
  const label = MON[target.getMonth()] + " " + target.getDate() + ", " + target.getFullYear();
  const start = parseDate(st.startDate) || new Date(target.getTime() - 365 * DAY);
  const p = target > start ? clamp((now - start) / (target - start), 0, 1) : 1;
  if (dd < 0) return { big: String(-dd), unit: plural(-dd, "day ago", "days ago"), sub: label, p: 1 };
  if (dd === 0) return { big: "Today", unit: "", sub: label, p: 1 };
  if (st.showHours === true) return { big: String(d), unit: plural(d, "day", "days"), sub: hr + " " + plural(hr, "hour", "hours"), p };
  return { big: String(dd), unit: plural(dd, "day", "days"), sub: label, p };
}

function daysView(c, title, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  if (aw >= ah * 1.8) {
    const f = clamp(Math.min(aw / 260, ah / 90), 0.7, 3);
    const numW = Math.max(50, aw * 0.45), colW = Math.max(60, aw - numW - 16);
    const side = al.mode === "right" ? "trailing" : al.mode === "center" ? "center" : "leading";
    const left = VStack({ spacing: 0, alignment: side, width: numW },
      Text({ text: c.big, size: fitSize(c.big, 64 * f, numW), weight: "semibold", color: "accent", monospacedDigit: true, align: side, lineLimit: 1 }),
      c.unit ? Text({ text: c.unit, size: fitSize(c.unit, 16 * f, numW), color: "secondary", align: side, lineLimit: 1 }) : null);
    const right = VStack({ spacing: 2 * f, alignment: side, width: colW },
      Text({ text: title, size: fitSize(title, 22 * f, colW), weight: "semibold", align: side, lineLimit: 1 }),
      c.sub ? Text({ text: c.sub, size: fitSize(c.sub, 14 * f, colW), color: "secondary", align: side, lineLimit: 1 }) : null);
    return HStack({ spacing: 16, alignment: "center", padding: PAD, width: w, height: h }, ...(al.mode === "right" ? [right, left] : [left, right]));
  }
  const f = clamp(Math.min(aw / 110, ah / 130), 0.7, 3.5);
  return page(w, h, al.v, 2 * f,
    Text({ text: title, size: fitSize(title, 15 * f, aw), weight: "semibold", color: "accent", align: al.v, lineLimit: 1 }),
    Text({ text: c.big, size: fitSize(c.big, 64 * f, aw), weight: "semibold", monospacedDigit: true, align: al.v, lineLimit: 1 }),
    c.unit ? Text({ text: c.unit, size: fitSize(c.unit, 15 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }) : null,
    c.sub ? Text({ text: c.sub, size: fitSize(c.sub, 12 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }) : null);
}

function ringView(c, title, al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const mk = (r) => Ring({ value: c.p, color: "accent", size: r },
    VStack({ spacing: 0, alignment: "center" },
      Text({ text: c.big, size: fitSize(c.big, r / 3, r * 0.62), weight: "semibold", monospacedDigit: true, align: "center", lineLimit: 1 }),
      c.unit ? Text({ text: c.unit, size: clamp(r / 9, 8, 28), color: "secondary", align: "center", lineLimit: 1 }) : null));
  if (aw >= ah * 1.7) {
    const r = clamp(ah, 40, 300), colW = Math.max(40, aw - r - 16);
    const side = al.mode === "right" ? "trailing" : al.mode === "center" ? "center" : "leading";
    const info = VStack({ spacing: 3, alignment: side, width: colW },
      Text({ text: title, size: fitSize(title, clamp(r * 0.2, 12, 40), colW), weight: "semibold", align: side, lineLimit: 1 }),
      c.sub ? Text({ text: c.sub, size: fitSize(c.sub, clamp(r * 0.12, 10, 24), colW), color: "secondary", align: side, lineLimit: 1 }) : null);
    return HStack({ spacing: 16, alignment: "center", padding: PAD, width: w, height: h }, ...(al.mode === "right" ? [info, mk(r)] : [mk(r), info]));
  }
  const lab = ah >= 110;
  const r = clamp(Math.min(aw, ah - (lab ? 26 : 0)), 36, 300);
  return page(w, h, al.v, 6, mk(r),
    lab ? Text({ text: title, size: fitSize(title, clamp(r * 0.11, 11, 24), aw), color: "secondary", align: al.v, lineLimit: 1 }) : null);
}

export default defineWidget({
  sources: { now: timer(60) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const t = ctx.data && ctx.data.now && num(ctx.data.now.now) ? ctx.data.now.now : Date.now();
    const c = compute(new Date(t), st);
    const title = typeof st.title === "string" && st.title.trim() !== "" ? st.title.trim() : "Countdown";
    const w = ctx.size.width, h = ctx.size.height;
    return st.style === "ring" ? ringView(c, title, al, w, h) : daysView(c, title, al, w, h);
  },
});
