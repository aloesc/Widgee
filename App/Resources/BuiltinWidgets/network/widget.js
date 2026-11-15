import { defineWidget, VStack, HStack, Spacer, Text, Image, Sparkline, system } from "widgee";

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

const HISTORY = 60;
const hist = { down: [], up: [] };
function push(a, v) { a.push(v); while (a.length > HISTORY) a.shift(); }

// Скорость -> { v, u }: байты (КБ = 1024) или биты (кило = 1000).
function speed(n, bits) {
  if (!num(n)) return { v: DASH, u: bits ? "bit/s" : "B/s" };
  const base = bits ? 1000 : 1024, x = bits ? n * 8 : n;
  const u = bits ? ["bit/s", "Kbit/s", "Mbit/s", "Gbit/s"] : ["B/s", "KB/s", "MB/s", "GB/s"];
  let i = 0, y = x;
  while (y >= base && i < u.length - 1) { y /= base; i++; }
  return { v: i === 0 || y >= 100 ? String(Math.round(y)) : y.toFixed(1), u: u[i] };
}
const col = (st, k, d) => (typeof st[k] === "string" && HEX.test(st[k]) ? st[k] : d);

function numbers(m, al, w, h, cd, cu) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const wide = aw >= ah * 1.8;
  const f = wide ? clamp(Math.min(aw / 250, ah / 70), 0.8, 3) : clamp(Math.min(aw / 140, ah / 120), 0.7, 3);
  const block = (label, icon, s, c) => VStack({ spacing: 2 * f, alignment: al.lead },
    hrow(al.lead, 4 * f, Image({ systemName: icon, size: 13 * f, color: c }), Text({ text: label, size: 12 * f, color: "secondary", lineLimit: 1 })),
    hrow(al.lead, 4 * f, Text({ text: s.v, size: 28 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 }),
      Text({ text: s.u, size: 12 * f, color: "secondary", lineLimit: 1 })));
  const a = block("Download", "arrow.down", m.down, cd), b = block("Upload", "arrow.up", m.up, cu);
  if (wide) return HStack({ spacing: 24 * f, alignment: "center", padding: PAD, width: w, height: h },
    ...(al.mode === "right" ? [Spacer(), a, b] : al.mode === "left" ? [a, b, Spacer()] : [Spacer(), a, b, Spacer()]));
  return page(w, h, al.lead, 10 * f, a, b);
}

function graphs(m, al, w, h, cd, cu) {
  const aw = w - PAD * 2, ah = h - PAD * 2;
  const f = clamp(Math.min(aw / 180, ah / 130), 0.8, 2.6);
  const gh = clamp((ah - 2 * (18 * f + 8 * f)) / 2, 18, 240);
  const series = (label, icon, s, vals, c) => VStack({ spacing: 3 * f, alignment: al.lead },
    split(al, 6 * f,
      HStack({ spacing: 4 * f }, Image({ systemName: icon, size: 12 * f, color: c }), Text({ text: label, size: 12 * f, color: "secondary", lineLimit: 1 })),
      Text({ text: s.v + " " + s.u, size: 13 * f, weight: "semibold", monospacedDigit: true, lineLimit: 1 })),
    Sparkline({ values: vals.length > 1 ? vals.slice() : [0, 0], color: c, height: gh, fill: true }));
  return page(w, h, al.lead, 8 * f, series("Download", "arrow.down", m.down, hist.down, cd), series("Upload", "arrow.up", m.up, hist.up, cu));
}

export default defineWidget({
  sources: { network: system("network", { interval: 2 }) },
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const n = ctx.data ? ctx.data.network : null;
    const bits = st.units === "Bits";
    const d = n && num(n.downBytesPerSec) ? n.downBytesPerSec : null, u = n && num(n.upBytesPerSec) ? n.upBytesPerSec : null;
    push(hist.down, d === null ? 0 : d); push(hist.up, u === null ? 0 : u);
    const m = { down: speed(d, bits), up: speed(u, bits) };
    const cd = col(st, "downColor", "#0A84FF"), cu = col(st, "upColor", "#FF9F0A");
    return st.style === "graph" ? graphs(m, al, w, h, cd, cu) : numbers(m, al, w, h, cd, cu);
  },
});
