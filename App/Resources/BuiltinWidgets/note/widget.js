import { defineWidget, VStack, Spacer, Text } from "widgee";

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

// Подбор размера шрифта: текст (грубая оценка 0.6 em на символ) должен поместиться в aw x ah.
function fitText(text, aw, ah, maxS, minS) {
  const lh = 1.25;
  for (let s = Math.floor(maxS); s >= minS; s--) {
    const perLine = Math.max(1, Math.floor(aw / (s * 0.6)));
    const lines = Math.ceil(text.length / (perLine * 0.9));
    if (lines * s * lh <= ah) return { size: s, lines };
  }
  return { size: minS, lines: Math.max(1, Math.floor(ah / (minS * lh))) };
}

export default defineWidget({
  render(ctx) {
    const st = ctx.settings || {};
    const al = alignInfo(ctx);
    const w = ctx.size.width, h = ctx.size.height;
    const aw = w - PAD * 2, ah = h - PAD * 2;
    const quote = st.style === "quote";
    const raw = typeof st.text === "string" ? st.text.trim() : "";
    const text = raw === "" ? "Edit this note in settings" : raw;
    const author = typeof st.author === "string" ? st.author.trim() : "";
    const color = raw === "" ? "secondary" : st.accent === true ? "accent" : "primary";
    const side = quote ? al.v : al.lead;
    const manual = num(st.fontSize) && st.fontSize > 0 ? clamp(st.fontSize, 8, 120) : 0;
    const mark = quote && ah >= 100 ? clamp(Math.min(aw, ah) * 0.3, 22, 90) : 0;
    const markH = mark ? mark * 0.75 : 0;
    const auth = author !== "" ? "— " + author : "";
    const authS = auth ? clamp(Math.min(aw, ah) * 0.1, 10, 24) : 0;
    const authH = auth ? authS * 1.4 + 4 : 0;
    const areaH = Math.max(14, ah - markH - authH - 8);
    const maxS = quote ? Math.min(60, Math.min(aw, ah) * 0.32) : Math.min(72, Math.min(aw, ah) * 0.4);
    const fit = fitText(text, aw, areaH, manual || Math.max(12, maxS), manual || 10);
    const size = manual || fit.size;
    const lines = clamp(Math.floor(areaH / (size * 1.25)), 1, 50);
    return page(w, h, side, 6,
      mark ? Text({ text: "“", size: mark, weight: "bold", color: "accent", align: side, height: markH, lineLimit: 1 }) : null,
      Text({ text, size, weight: quote ? "semibold" : "regular", color, align: side, lineLimit: lines }),
      auth ? Text({ text: auth, size: fitSize(auth, authS, aw), color: "secondary", align: side, lineLimit: 1 }) : null);
  },
});
