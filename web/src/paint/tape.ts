// Paints one repeat of a tape style. Used by the atlas page (what the world draws) and by every
// preview in the menus, so a style looks the same in both.
//
// The strip must tile without a seam: whatever leaves the right edge comes back in at the left.
// So every repeating thing (stripes, blocks, chevrons, text cells) is fitted to a whole number of
// periods per tile, and anything sitting on the seam (separators) is drawn at both ends.
import { capRatio, ensureFont, fontSpec } from './fonts';
import type { Pattern, Separator, Style, TapeText } from './types';

/** Every character a style prints, so its face can be fetched before painting. */
export function sampleText(style: Style): string {
  return style.text ? style.text.items.join('') : '';
}

/** Resolves when everything `style` needs to paint correctly has loaded. */
export async function prepare(style: Style): Promise<void> {
  if (style.text) await ensureFont(style.text.font, sampleText(style), style.text.italic);
}

function polygon(ctx: CanvasRenderingContext2D, pts: number[]): void {
  ctx.beginPath();
  ctx.moveTo(pts[0], pts[1]);
  for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]);
  ctx.closePath();
  ctx.fill();
}

function paintPattern(ctx: CanvasRenderingContext2D, p: Pattern, w: number, h: number): void {
  ctx.fillStyle = p.color;

  switch (p.type) {
    case 'diagonal': {
      const k = Math.max(1, Math.round(w / (2 * p.size * h)));
      const period = w / k;
      const stripe = period / 2;
      const slant = h * Math.tan((p.angle * Math.PI) / 180);
      for (let i = -3; i <= k + 3; i++) {
        const x0 = i * period;
        polygon(ctx, [x0, h, x0 + stripe, h, x0 + stripe + slant, 0, x0 + slant, 0]);
      }
      break;
    }
    case 'blocks': {
      const k = Math.max(1, Math.round(w / (2 * p.size * h)));
      const bw = w / (2 * k);
      for (let i = 0; i < k; i++) ctx.fillRect((2 * i + 1) * bw, 0, bw, h);
      break;
    }
    case 'checker': {
      const rows = Math.max(1, Math.min(4, Math.round(1 / p.size)));
      const k = Math.max(1, Math.round(w / (2 * p.size * h)));
      const cw = w / (2 * k);
      const rh = h / rows;
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < 2 * k; c++) if ((r + c) % 2 === 1) ctx.fillRect(c * cw, r * rh, cw, rh);
      }
      break;
    }
    case 'chevron': {
      const k = Math.max(1, Math.round(w / (2 * p.size * h)));
      const period = w / k;
      const t = period / 2;
      const tip = h / 2;
      for (let i = -2; i <= k + 1; i++) {
        const x0 = i * period;
        polygon(ctx, [x0, 0, x0 + t, 0, x0 + t + tip, h / 2, x0 + t, h, x0, h, x0 + tip, h / 2]);
      }
      break;
    }
    case 'band': {
      const bh = Math.min(0.9, Math.max(0.05, p.size)) * h;
      ctx.fillRect(0, (h - bh) / 2, w, bh);
      break;
    }
    case 'dashes': {
      const k = Math.max(1, Math.round(w / (2 * p.size * h)));
      const dw = w / (2 * k);
      const bh = h * 0.3;
      for (let i = 0; i < k; i++) ctx.fillRect(2 * i * dw + dw / 2, (h - bh) / 2, dw, bh);
      break;
    }
  }
}

function star(ctx: CanvasRenderingContext2D, cx: number, cy: number, ro: number, ri: number): void {
  const pts: number[] = [];
  for (let i = 0; i < 10; i++) {
    const r = i % 2 === 0 ? ro : ri;
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    pts.push(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
  }
  polygon(ctx, pts);
}

function paintSeparator(ctx: CanvasRenderingContext2D, kind: Separator, x: number, h: number): void {
  const cy = h / 2;
  switch (kind) {
    case 'dot':
      ctx.beginPath();
      ctx.arc(x, cy, h * 0.09, 0, Math.PI * 2);
      ctx.fill();
      break;
    case 'star':
      star(ctx, x, cy + h * 0.015, h * 0.2, h * 0.08);
      break;
    case 'bar':
      ctx.fillRect(x - h * 0.03, cy - h * 0.27, h * 0.06, h * 0.54);
      break;
    case 'slash': {
      const s = h * 0.3;
      const t = h * 0.06;
      polygon(ctx, [x - s * 0.45 - t / 2, cy + s, x - s * 0.45 + t / 2, cy + s, x + s * 0.45 + t / 2, cy - s, x + s * 0.45 - t / 2, cy - s]);
      break;
    }
    case 'diamond': {
      const d = h * 0.15;
      polygon(ctx, [x, cy - d, x + d, cy, x, cy + d, x - d, cy]);
      break;
    }
    case 'cross': {
      const a = h * 0.21;
      const t = h * 0.085;
      ctx.fillRect(x - t / 2, cy - a, t, a * 2);
      ctx.fillRect(x - a, cy - t / 2, a * 2, t);
      break;
    }
    case 'chevron': {
      const s = h * 0.22;
      const t = h * 0.09;
      polygon(ctx, [x - s * 0.5, cy - s, x - s * 0.5 + t, cy - s, x + s * 0.5 + t, cy, x - s * 0.5 + t, cy + s, x - s * 0.5, cy + s, x + s * 0.5, cy]);
      break;
    }
  }
}

/**
 * Lays the wording out like printed tape: each item at its natural width, the space left over
 * shared out evenly between them, and a separator in the middle of each gap. Only when the words
 * do not fit at all are they all narrowed, by the same amount, so no one item is squashed.
 *
 * The first gap is split across the seam (half at each end of the tile), which is what makes the
 * repeat continuous.
 */
function paintText(ctx: CanvasRenderingContext2D, t: TapeText, w: number, h: number, edge: number): void {
  const cap = capRatio(ctx, t.font);
  const px = (t.size * h) / cap;
  const capH = px * cap;
  const pad = t.plate ? t.plate.padding * h : 0;
  const baseline = h / 2 + capH / 2;

  ctx.font = fontSpec(t.font, px, t.italic);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  // letterSpacing is in Chromium since 99; FiveM's is 103. It adds space after the last letter
  // too, which measureText includes: take it back off so centring is true.
  const spacing = t.spacing * px;
  (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = `${spacing.toFixed(2)}px`;

  const labels: string[] = [];
  for (let r = 0; r < t.repeats; r++) labels.push(...t.items);
  const n = labels.length;
  const widths = labels.map((l) => Math.max(0, ctx.measureText(l).width - spacing) + pad * 2);
  const total = widths.reduce((a, b) => a + b, 0);

  const minGap = h * (t.separator !== 'none' ? 0.9 : 0.6) + (t.plate ? h * 0.2 : 0);
  let sx = 1;
  let gap = (w - total) / n;
  if (gap < minGap) {
    gap = minGap;
    const textOnly = total - n * pad * 2;
    sx = textOnly > 0 ? Math.max(0.3, (w - n * minGap - n * pad * 2) / textOnly) : 1;
  }

  let x = gap / 2;
  const marks: number[] = [0, w];
  for (let i = 0; i < n; i++) {
    const textW = (widths[i] - pad * 2) * sx;
    const boxW = textW + pad * 2;
    const cx = x + boxW / 2;

    if (t.plate) {
      const ph = Math.max(capH + h * 0.18, h - edge * 2 - h * 0.14);
      ctx.fillStyle = t.plate.color;
      ctx.fillRect(cx - boxW / 2, (h - ph) / 2, boxW, ph);
    }

    ctx.save();
    ctx.translate(cx + (spacing * sx) / 2, baseline);
    ctx.scale(sx, 1);
    if (t.outline) {
      ctx.lineJoin = 'round';
      ctx.lineWidth = (t.outline.width * px) / sx;
      ctx.strokeStyle = t.outline.color;
      ctx.strokeText(labels[i], 0, 0);
    }
    ctx.fillStyle = t.color;
    ctx.fillText(labels[i], 0, 0);
    ctx.restore();

    x += boxW + gap;
    if (i < n - 1) marks.push(x - gap / 2);
  }

  if (t.separator !== 'none') {
    ctx.fillStyle = t.separatorColor || t.color;
    // Including both ends of the tile, so the one on the seam is whole.
    for (const m of marks) paintSeparator(ctx, t.separator, m, h);
  }
}

/**
 * Paints one repeat of `style` into the rectangle (0, 0, w, h) of `ctx`. The caller has called
 * `prepare(style)` first, or accepts a fallback face until it paints again.
 */
export function paintTape(ctx: CanvasRenderingContext2D, style: Style, w: number, h: number): void {
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, w, h);
  ctx.clip();

  ctx.fillStyle = style.base;
  ctx.fillRect(0, 0, w, h);

  if (style.pattern) paintPattern(ctx, style.pattern, w, h);

  const edge = style.edges ? style.edges.size * h : 0;
  if (style.edges) {
    ctx.fillStyle = style.edges.color;
    ctx.fillRect(0, 0, w, edge);
    ctx.fillRect(0, h - edge, w, edge);
  }

  if (style.text) paintText(ctx, style.text, w, h, edge);

  ctx.restore();
}

/**
 * Halves a canvas, with the browser's best filter. Done step by step from the full-size strip,
 * this is a mip chain: what the game would normally make for a texture, and does not make for a
 * DUI texture (client/tape/atlas.lua picks a level by distance).
 */
export function halve(src: HTMLCanvasElement): HTMLCanvasElement {
  const out = document.createElement('canvas');
  out.width = Math.max(1, src.width >> 1);
  out.height = Math.max(1, src.height >> 1);
  const ctx = out.getContext('2d')!;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(src, 0, 0, out.width, out.height);
  return out;
}
