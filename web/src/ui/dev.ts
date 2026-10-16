// Browser preview only (npm run dev, never in the build): plays client/nui.lua's part.
// Pick what to look at with the address's hash: #place, #look, #picker, #holders, #studio, #admin.
import styles from './dev-styles.json';
import type { ActReply, Snapshot } from './admin/types';

function send(msg: Record<string, unknown>): void {
  window.postMessage(msg, '*');
}

// configs/holders.lua, as the game would send it (the pictures from images/holders/).
const HOLDERS: [string, string, number][] = [
  ['post', 'Delineator post', 1.05],
  ['cone_orange', 'Traffic cone (orange)', 0.711],
  ['cone_orange_band', 'Traffic cone (orange, one band)', 0.711],
  ['cone_orange_plain', 'Traffic cone (orange, plain)', 0.711],
  ['cone_highway', 'Highway cone (orange, 90 cm)', 0.914],
  ['cone_highway_round', 'Highway cone (round base)', 0.914],
  ['cone_orange_45', 'Traffic cone (orange, 45 cm)', 0.457],
  ['cone_orange_45_plain', 'Traffic cone (orange, 45 cm, plain)', 0.457],
  ['cone_mini', 'Mini cone (orange, 30 cm)', 0.305],
  ['cone_red_white_75', 'Traffic cone (red / white, 75 cm)', 0.75],
  ['cone_red_white_50', 'Traffic cone (red / white, 50 cm)', 0.5],
  ['cone_red_white_100', 'Traffic cone (red / white, 100 cm)', 1],
  ['cone_yellow', 'Traffic cone (yellow)', 0.711],
  ['cone_lime', 'Traffic cone (lime)', 0.711],
  ['cone_blue', 'Traffic cone (blue)', 0.711],
  ['cone_white', 'Traffic cone (white)', 0.711],
  ['cone_black', 'Traffic cone (black / yellow)', 0.711],
  ['cone_pink', 'Traffic cone (pink)', 0.711],
  ['cone_green', 'Traffic cone (green)', 0.711],
  ['cone_hazard', 'Hazard cone (yellow / black)', 0.711],
  ['cone_red_45', 'Traffic cone (red, 45 cm)', 0.457],
];
const picture = (id: string) => new URL(`../../../images/holders/${id}.png`, import.meta.url).href;
const holderCards = HOLDERS.map(([id, label, height]) => ({ id, label, height, image: picture(id) }));

const TOGGLES: [string, string, boolean][] = [
  ['Tear.Enabled', 'tape', true],
  ['Tear.People', 'tape', true],
  ['Physics.Enabled', 'tape', true],
  ['Wind.Enabled', 'tape', true],
  ['Holders.Knock', 'holders', true],
  ['Holders.Vehicles', 'holders', true],
  ['Holders.Kick', 'holders', true],
  ['Holders.Run', 'holders', true],
  ['Holders.StandUp', 'holders', true],
  ['Placement.Posts', 'placing', true],
  ['Placement.Chain', 'placing', true],
  ['Access.OthersTapes', 'placing', true],
  ['Item.Enabled', 'item', true],
  ['Item.Consume', 'item', false],
  ['Item.Refund', 'item', true],
  ['Persist', 'saving', true],
  ['PersistChoice', 'saving', true],
];

const now = Math.floor(Date.now() / 1000);
const snapshot: Snapshot = {
  now,
  total: 800,
  toggles: TOGGLES.map(([key, group, on]) => ({ key, group, on, default: on })),
  offStyles: ['sheriff_line_tan', 'park_ranger'],
  offHolders: ['cone_pink', 'cone_lime'],
  holders: HOLDERS.map(([id, label, height]) => ({ id, label, height, model: id, image: picture(id) })),
  tapes: [
    ['police_line', 'Samuel Black', 'Vespucci Blvd, Little Seoul', 6.2, false, false, 40, 12],
    ['crime_scene', 'Jessica Hale', 'Strawberry Ave, Strawberry', 11.4, true, false, 300, 210],
    ['police_line_bold', 'Samuel Black', 'Vespucci Blvd, Little Seoul', 4.8, false, true, 520, 14],
    ['sheriff_line', 'Devon Price', 'Route 68, Grand Senora Desert', 14.9, false, false, 3900, 3120],
    ['crime_scene', null, 'Alta St, Downtown', 8.1, false, false, 7400, 880],
  ].map(([style, owner, street, length, torn, down, age, distance], i) => {
    const s = styles.find((x) => x.id === style) ?? styles[0];
    return {
      id: 41 - i * 3,
      style: s.id,
      label: s.label,
      owner: owner as string | null,
      script: owner === null,
      created: now - (age as number),
      length: length as number,
      torn: torn as boolean,
      down: down as boolean,
      persist: i !== 1,
      a: { x: 0, y: 0, z: 0 },
      b: { x: 1, y: 0, z: 0 },
      street: street as string,
      distance: distance as number,
    };
  }),
};

/** Plays server/admin.lua for the browser preview. */
export function adminAct(verb: string, data: Record<string, unknown>): ActReply {
  const idList = Array.isArray(data.ids) ? (data.ids as string[]) : [];
  if (verb === 'toggle') {
    snapshot.toggles = snapshot.toggles.map((tg) => (tg.key === data.key ? { ...tg, on: data.on === true } : tg));
  } else if (verb === 'styles' || verb === 'holders') {
    const key = verb === 'styles' ? 'offStyles' : 'offHolders';
    const set = new Set(snapshot[key]);
    for (const id of idList) data.on ? set.delete(id) : set.add(id);
    snapshot[key] = [...set];
  } else if (verb === 'persist') {
    snapshot.tapes = snapshot.tapes.map((r) => (r.id === data.id ? { ...r, persist: data.on === true } : r));
  } else if (verb === 'remove') {
    snapshot.tapes = snapshot.tapes.filter((r) => r.id !== data.id);
  } else if (verb === 'removeTorn') {
    snapshot.tapes = snapshot.tapes.filter((r) => !r.torn);
  } else if (verb === 'removeAll') {
    snapshot.tapes = [];
  }
  return { ok: true, snapshot: structuredClone(snapshot) };
}

export function start(): void {
  // A grey-green stand-in for the game behind the page.
  document.body.style.background = "linear-gradient(160deg, #5d6b5a, #3d4a52)";
  // Two Tape Studio styles, one of them this player's, for the picker's Custom and Yours.
  const studio = [
    { ...styles[1], id: 'c_dev001', label: 'Davis Block Party', category: 'crime', custom: true, author: 'Samuel Black', authorKey: 'a1b2c3d4' },
    { ...styles[4], id: 'c_dev002', label: 'Ranger Station', category: 'utility', custom: true, author: 'Jessica Hale', authorKey: 'ffee0011' },
  ];
  send({ action: 'init', styles: [...styles, ...studio], canStudio: true, me: { key: 'a1b2c3d4', name: 'Samuel Black' } });

  const view = location.hash.slice(1) || 'place';
  if (view === 'place') {
    send({
      action: 'hud',
      hud: {
        mode: 'place',
        styleId: 'crime_scene',
        title: 'Crime Scene',
        line: '6.4 m',
        lineKind: 'ok',
        keys: [
          { k: 'LMB', t: 'Tie off here' },
          { k: 'Wheel', t: 'Style' },
          { k: 'G', t: 'All styles' },
          { k: 'RMB', t: 'Done' },
        ],
      },
    });
  } else if (view === 'look') {
    send({
      action: 'hud',
      hud: { mode: 'look', styleId: 'police_line', keys: [{ k: 'G', t: 'Change style' }, { k: 'Alt', t: 'Hold to take down' }] },
    });
    let p = 0;
    window.setInterval(() => {
      p = p >= 1 ? 0 : p + 0.02;
      send({ action: 'progress', value: p });
    }, 40);
  } else if (view === 'picker') {
    send({ action: 'picker', open: true, selected: 'crime_scene' });
  } else if (view === 'holders') {
    send({ action: 'holders', open: true, list: holderCards, selected: 'cone_orange' });
  } else if (view.startsWith('admin')) {
    send({ action: 'off', styles: snapshot.offStyles });
    send({ action: 'admin', open: true, snapshot: structuredClone(snapshot) });
  } else if (view === 'studio') {
    send({ action: 'studio', open: true, startFrom: 'police_line' });
  }
}
