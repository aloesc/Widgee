import { defineWidget, VStack, HStack, Spacer, Text, Image, LinearBar, Ring, system } from "widgee";

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

function pickColor(st, b) {
  if (st.colorMode === "Accent") return "accent";
  if (st.colorMode === "Custom" && typeof st.color === "string" && HEX.test(st.color)) return st.color;
  if (b.isCharging) return "#30D158";
  if (b.level < 0.2) return "#FF453A";
  if (b.level < 0.4) return "#FF9F0A";
  return "#30D158";
}
function iconFor(b) {
  if (b.isCharging) return "battery.100.bolt";
  const l = b.level;
  return l >= 0.88 ? "battery.100" : l >= 0.63 ? "battery.75" : l >= 0.38 ? "battery.50" : l >= 0.13 ? "battery.25" : "battery.0";
}
function statusText(b) {
  if (b.isCharging) return "Charging";
  if (b.isPluggedIn) return b.level >= 0.95 ? "Fully charged" : "On AC power";
  return "On battery";
}
function detailText(b) {
  if (b.isCharging || b.isPluggedIn) return "Power adapter connected";
  return b.level < 0.2 ? "Low battery" : "Using battery power";
}

function noBattery(al, w, h) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = clamp(Math.min(aw / 150, ah / 80), 0.8, 3);
  return page(w, h, al.v, 4 * f,
    Image({ systemName: "desktopcomputer", size: 30 * f, color: "secondary" }),
    Text({ text: "No battery", size: fitSize("No battery", 16 * f, aw), weight: "semibold", align: al.v, lineLimit: 1 }),
    Text({ text: "Running on AC power", size: fitSize("Running on AC power", 11 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }));
}

function ringView(b, al, w, h, c) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const pct = Math.round(b.level * 100) + "%";
  const status = statusText(b);
  const mk = (r) => Ring({ value: clamp01(b.level), color: c, size: r },
    VStack({ spacing: 0, alignment: "center" },
      r >= 90 && b.isCharging ? Image({ systemName: "bolt.fill", size: r * 0.14, color: c }) : null,
      Text({ text: pct, size: r / 3.8, weight: "semibold", monospacedDigit: true, lineLimit: 1 })));
  if (aw >= ah * 1.7) {
    const r = clamp(ah, 40, 300), colW = Math.max(40, aw - r - 16);
    const big = fitSize("100%", clamp(r * 0.4, 14, 120), colW);
    const small = fitSize("Fully charged", clamp(big * 0.4, 10, 40), colW);
    const side = al.mode === "right" ? "trailing" : al.mode === "center" ? "center" : "leading";
    const info = VStack({ spacing: 3, alignment: side, width: colW },
      Text({ text: pct, size: big, weight: "semibold", monospacedDigit: true, align: side, lineLimit: 1 }),
      Text({ text: status, size: small, color: "secondary", align: side, lineLimit: 1 }));
    const kids = al.mode === "right" ? [info, mk(r)] : [mk(r), info];
    return HStack({ spacing: 16, alignment: "center", padding: PAD, width: w, height: h }, ...kids);
  }
  const lab = ah >= 110;
  const lh = lab ? clamp(ah * 0.12, 13, 26) * 1.4 + 6 : 0;
  const r = clamp(Math.min(aw, ah - lh), 36, 300);
  return page(w, h, al.v, 6, mk(r),
    lab ? Text({ text: status, size: fitSize(status, clamp(r * 0.11, 11, 24), aw), color: "secondary", align: al.v, lineLimit: 1 }) : null);
}

function barView(b, al, w, h, c) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = clamp(Math.min(aw / 200, ah / 70), 0.8, 3.2);
  const head = split(al, 6 * f,
    HStack({ spacing: 5 * f }, Image({ systemName: iconFor(b), size: 16 * f, color: c }),
      Text({ text: "Battery", size: 14 * f, color: "secondary", lineLimit: 1 })),
    Text({ text: Math.round(b.level * 100) + "%", size: 22 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 }));
  return page(w, h, al.lead, 7 * f, head, LinearBar({ value: clamp01(b.level), color: c, height: 8 * f }),
    Text({ text: statusText(b), size: fitSize(statusText(b), 12 * f, aw), color: "secondary", align: al.lead, lineLimit: 1 }));
}

function statusView(b, al, w, h, c) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = clamp(Math.min(aw / 130, ah / 130), 0.8, 3);
  const st = statusText(b), dt = detailText(b);
  return page(w, h, al.v, 6 * f,
    hrow(al.v, 8 * f, Image({ systemName: iconFor(b), size: 30 * f, color: c }),
      Text({ text: Math.round(b.level * 100) + "%", size: 40 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
    LinearBar({ value: clamp01(b.level), color: c, height: 10 * f }),
    Text({ text: st, size: fitSize(st, 15 * f, aw), weight: "medium", align: al.v, lineLimit: 1 }),
    Text({ text: dt, size: fitSize(dt, 11 * f, aw), color: "secondary", align: al.v, lineLimit: 1 }));
}

export default defineWidget({
  sources: { battery: system("battery", { interval: 30 }) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const raw = ctx.data ? ctx.data.battery : null;
    if (!raw || !num(raw.level)) return noBattery(al, w, h);
    const b = { level: clamp01(raw.level), isCharging: raw.isCharging === true, isPluggedIn: raw.isPluggedIn === true || raw.isCharging === true };
    const c = pickColor(st, b);
    if (st.style === "bar") return barView(b, al, w, h, c);
    if (st.style === "status") return statusView(b, al, w, h, c);
    return ringView(b, al, w, h, c);
  },
});
