// The page a DUI loads (atlas.html). Nobody looks at it: the game reads its one canvas as a
// texture and draws every tape in the world from it (client/tape/atlas.lua).
//
// Lua tells it, for a slot, which style to paint there:
//   { action: 'paint', slot, serial, style }
//   { action: 'clear', slot, serial }
// and the page paints the style's strip and its smaller levels into that slot.
import { prepare, paintTape, halve } from '../paint/tape';
import { ATLAS, LODS, SLOT_COUNT, SLOT_H, SLOT_W, slotOrigin } from '../paint/layout';
import { TILE_H, TILE_W, type Style } from '../paint/types';

interface PaintMessage {
  action: 'paint';
  slot: number;
  serial: number;
  style: Style;
}

interface ClearMessage {
  action: 'clear';
  slot: number;
  serial: number;
}

const canvas = document.getElementById('atlas') as HTMLCanvasElement;
canvas.width = canvas.height = ATLAS;
const ctx = canvas.getContext('2d')!;

const strip = document.createElement('canvas');
strip.width = TILE_W;
strip.height = TILE_H;
const stripCtx = strip.getContext('2d')!;

/** Newest request per slot. A slot can be given a new style while the old one's face loads. */
const latest = new Map<number, number>();

async function paint(msg: PaintMessage): Promise<void> {
  await prepare(msg.style);
  if (latest.get(msg.slot) !== msg.serial) return;

  stripCtx.clearRect(0, 0, TILE_W, TILE_H);
  paintTape(stripCtx, msg.style, TILE_W, TILE_H);

  const [sx, sy] = slotOrigin(msg.slot);
  ctx.clearRect(sx, sy, SLOT_W, SLOT_H);

  let level: HTMLCanvasElement = strip;
  for (let i = 0; i < LODS.length; i++) {
    const [lx, ly, lw, lh] = LODS[i];
    if (i > 0) level = halve(level);
    ctx.drawImage(level, 0, 0, level.width, level.height, sx + lx, sy + ly, lw, lh);
  }
}

window.addEventListener('message', (event: MessageEvent) => {
  const msg = event.data as PaintMessage | ClearMessage | undefined;
  if (!msg || typeof msg !== 'object' || typeof msg.slot !== 'number') return;
  if (msg.slot < 0 || msg.slot >= SLOT_COUNT) return;

  // Lua re-sends paints until it hears the page is up; only ever go forwards.
  const prev = latest.get(msg.slot);
  if (prev !== undefined && msg.serial < prev) return;
  latest.set(msg.slot, msg.serial);

  if (msg.action === 'paint') {
    void paint(msg);
  } else if (msg.action === 'clear') {
    const [sx, sy] = slotOrigin(msg.slot);
    ctx.clearRect(sx, sy, SLOT_W, SLOT_H);
  }
});

// Say the page is listening. Lua re-sends everything when it hears this, and on a timer anyway
// in case a DUI page's request never reaches the resource.
const resource = location.host.replace(/^cfx-nui-/, '') || 'sd-policetape';
void fetch(`https://${resource}/atlasReady`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: '{}',
}).catch(() => undefined);
