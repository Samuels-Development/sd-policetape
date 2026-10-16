// Where each style sits on the atlas page. client/tape/atlas.lua has the same numbers (SLOT_*,
// LOD rectangles): change one, change both.
//
// The page is 2048 x 2048 and holds 40 slots, two across and twenty down, each 1024 x 100:
//
//   +--------------------------------------------------+ y 0
//   | level 0: 1024 x 64                               |
//   +------------------------+-----------+------+------+ y 66
//   | level 1: 512 x 32      | 2: 256x16 | 3:128x8     |
//   +------------------------+-----------+-------------+ y 98
//
// The levels are a mip chain made by hand: a DUI texture has none, so a tape far away would
// shimmer. Lua picks a level per segment by how big the tape is on screen.

export const ATLAS = 2048;
export const SLOT_W = 1024;
export const SLOT_H = 100;
export const SLOTS_PER_ROW = 2;
export const SLOT_COUNT = SLOTS_PER_ROW * Math.floor(ATLAS / SLOT_H);

/** x, y, w, h of each level inside a slot. */
export const LODS: ReadonlyArray<readonly [number, number, number, number]> = [
  [0, 0, 1024, 64],
  [0, 66, 512, 32],
  [514, 66, 256, 16],
  [772, 66, 128, 8],
];

export function slotOrigin(slot: number): [number, number] {
  return [(slot % SLOTS_PER_ROW) * SLOT_W, Math.floor(slot / SLOTS_PER_ROW) * SLOT_H];
}
