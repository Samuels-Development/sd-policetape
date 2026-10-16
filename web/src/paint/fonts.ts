// The typefaces tape can be printed in. All bundled and all under open licences (OFL / Apache):
// a tape has to look the same to every player, so nothing comes from the player's machine.
import '@fontsource-variable/oswald/wght.css';
import '@fontsource-variable/roboto-condensed/wght.css';
import '@fontsource-variable/teko/wght.css';
import '@fontsource/anton/400.css';
import '@fontsource/archivo-black/400.css';
import '@fontsource/barlow-condensed/700.css';
import '@fontsource/bebas-neue/400.css';
import '@fontsource/black-ops-one/400.css';
import '@fontsource/russo-one/400.css';
import '@fontsource/saira-stencil-one/400.css';
import '@fontsource/staatliches/400.css';
import type { FontKey } from './types';

export interface Face {
  key: FontKey;
  name: string;
  family: string;
  weight: number;
}

export const FACES: Face[] = [
  { key: 'oswald', name: 'Oswald', family: 'Oswald Variable', weight: 600 },
  { key: 'anton', name: 'Anton', family: 'Anton', weight: 400 },
  { key: 'bebas', name: 'Bebas Neue', family: 'Bebas Neue', weight: 400 },
  { key: 'barlow', name: 'Barlow Condensed', family: 'Barlow Condensed', weight: 700 },
  { key: 'roboto', name: 'Roboto Condensed', family: 'Roboto Condensed Variable', weight: 700 },
  { key: 'teko', name: 'Teko', family: 'Teko Variable', weight: 600 },
  { key: 'stencil', name: 'Saira Stencil', family: 'Saira Stencil One', weight: 400 },
  { key: 'archivo', name: 'Archivo Black', family: 'Archivo Black', weight: 400 },
  { key: 'russo', name: 'Russo One', family: 'Russo One', weight: 400 },
  { key: 'staatliches', name: 'Staatliches', family: 'Staatliches', weight: 400 },
  { key: 'blackops', name: 'Black Ops One', family: 'Black Ops One', weight: 400 },
];

const BY_KEY = new Map(FACES.map((f) => [f.key, f]));

export function face(key: FontKey): Face {
  return BY_KEY.get(key) ?? FACES[0];
}

/** A canvas `font` value. The fallbacks only ever show while the real face is on its way. */
export function fontSpec(key: FontKey, px: number, italic = false): string {
  const f = face(key);
  return `${italic ? 'italic ' : ''}${f.weight} ${px}px "${f.family}", "Arial Narrow", sans-serif`;
}

/**
 * Waits until a face can draw `sample` (each face ships as several unicode-range files, and only
 * the ones the text needs are fetched). Gives up after a second and a half rather than leave a
 * tape unpainted: the caller simply paints again when it is told the face has arrived.
 */
export async function ensureFont(key: FontKey, sample: string, italic = false): Promise<void> {
  const spec = fontSpec(key, 64, italic);
  if (document.fonts.check(spec, sample || 'A')) return;
  await Promise.race([
    document.fonts.load(spec, sample || 'A').catch(() => undefined),
    new Promise((resolve) => window.setTimeout(resolve, 1500)),
  ]);
}

/** Cap height of a face as a fraction of its em, measured once. Lets `size` mean the same on all of them. */
const capCache = new Map<FontKey, number>();

export function capRatio(ctx: CanvasRenderingContext2D, key: FontKey): number {
  const known = capCache.get(key);
  if (known) return known;
  ctx.save();
  ctx.font = fontSpec(key, 100);
  const m = ctx.measureText('H');
  ctx.restore();
  const ratio = m.actualBoundingBoxAscent > 1 ? m.actualBoundingBoxAscent / 100 : 0.72;
  // Only remember a measurement of the real face: a fallback's would stick.
  if (document.fonts.check(fontSpec(key, 64), 'H')) capCache.set(key, ratio);
  return ratio;
}
