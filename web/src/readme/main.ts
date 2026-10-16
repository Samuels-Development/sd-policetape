// The README's pictures, drawn by the painter the game draws tape with (src/paint/tape.ts), so what
// the README shows is what a server gets. Dev only: `npm run dev`, open /readme.html with one of
// the hashes below and screenshot #art at its own size. docs/previews/ holds what it made.
//
//   #banner             1920 x 840: the banner at the top of the README
//   #hero               1920 x 720: styles crossed over a scene, the way tape goes up
//   #styles-<category>  every built-in style of one category, three to a row
//   #holders            the post and the twenty cones
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/inter/700.css';
import '@fontsource/inter/800.css';
import '@fontsource/inter/900.css';
import { paintTape, prepare } from '../paint/tape';
import { TILE_H, TILE_W, type Style } from '../paint/types';
import builtins from '../ui/dev-styles.json';

const STYLES = builtins as unknown as Style[];
const byId = new Map(STYLES.map((s) => [s.id, s]));
const YELLOW = '#F6D10E';

const CATEGORIES: [string, string][] = [
  ['police', 'Police'],
  ['federal', 'Federal'],
  ['crime', 'Crime scene'],
  ['fire', 'Fire'],
  ['ems', 'Medical'],
  ['hazard', 'Hazard'],
  ['utility', 'Utility'],
  ['plain', 'Plain'],
  ['international', 'International'],
];

// configs/holders.lua: id, label, height (m)
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

const holderPic = (id: string) => new URL(`../../../images/holders/${id}.png`, import.meta.url).href;
const ingame = (name: string) => new URL(`../../../docs/previews/ingame/${name}.webp`, import.meta.url).href;
const adminShot = (name: string) => new URL(`../../../docs/previews/admin/${name}.webp`, import.meta.url).href;
const ROLL = new URL('../../../images/police_tape.png', import.meta.url).href;

const heightLabel = (m: number) => (m >= 1 ? `${m.toFixed(2)} m` : `${Math.round(m * 100)} cm`);

function el<K extends keyof HTMLElementTagNameMap>(tag: K, css: Partial<CSSStyleDeclaration> | string = {}, kids: (Node | string)[] = []): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  if (typeof css === 'string') e.style.cssText = css;
  else Object.assign(e.style, css);
  for (const k of kids) e.append(k);
  return e;
}

/** A length of tape `w` x `h` px: the style's repeat, painted at twice the size and shown at its own. */
async function strip(style: Style, w: number, h: number, shift = 0): Promise<HTMLCanvasElement> {
  await prepare(style);
  const scale = 2;
  const tile = document.createElement('canvas');
  tile.height = Math.round(h * scale);
  tile.width = Math.round((tile.height * TILE_W) / TILE_H);
  paintTape(tile.getContext('2d')!, style, tile.width, tile.height);
  const c = document.createElement('canvas');
  c.width = Math.round(w * scale);
  c.height = tile.height;
  const ctx = c.getContext('2d')!;
  for (let x = -shift * tile.width; x < c.width; x += tile.width) ctx.drawImage(tile, Math.round(x), 0);
  c.style.width = `${w}px`;
  c.style.height = `${h}px`;
  c.style.display = 'block';
  return c;
}

function art(w: number, h: number | null, css = ''): HTMLDivElement {
  const a = el('div', `position:relative;overflow:hidden;width:${w}px;${h ? `height:${h}px;` : ''}font-family:Inter,sans-serif;color:#ededef;background:#0c0d0f;${css}`);
  a.id = 'art';
  document.getElementById('root')!.replaceChildren(a);
  return a;
}

/** Tape stretched across a picture: tilted, with a sheen and a shadow under it. */
async function laid(style: Style, w: number, h: number, angle: number, css: string): Promise<HTMLDivElement> {
  const wrap = el('div', `position:absolute;${css};transform:rotate(${angle}deg);transform-origin:center;box-shadow:0 ${h * 0.25}px ${h * 0.5}px rgba(0,0,0,0.55)`);
  wrap.append(await strip(style, w, h, Math.random()));
  wrap.append(el('div', 'position:absolute;inset:0;background:linear-gradient(180deg,rgba(255,255,255,0.22),rgba(255,255,255,0) 38%,rgba(0,0,0,0) 62%,rgba(0,0,0,0.22))'));
  return wrap;
}

function grid(): HTMLDivElement {
  return el('div', 'position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,0.028) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,0.028) 1px,transparent 1px);background-size:48px 48px');
}

const CARD = 'border-radius:14px;overflow:hidden;border:1px solid rgba(255,255,255,0.14);box-shadow:0 30px 70px rgba(0,0,0,0.6)';

function card(src: string, css: string): HTMLDivElement {
  return el('div', `position:absolute;${css};${CARD};background:#000 url("${src}") center/cover no-repeat`);
}

/** A card of one part of a 1920 x 1080 screenshot, [x, y, w, h], shown `width` px wide. */
function cropCard(src: string, [x, y, w, h]: number[], left: number, top: number, width: number): HTMLDivElement {
  const s = width / w;
  return el('div', `position:absolute;left:${left}px;top:${top}px;width:${width}px;height:${Math.round(h * s)}px;${CARD};background:#000 url("${src}") ${-x * s}px ${-y * s}px/${1920 * s}px auto no-repeat`);
}

// -- banner ---------------------------------------------------------------------------------------
async function banner(): Promise<void> {
  const a = art(1920, 840, 'background:#0d1015');
  a.append(grid());
  a.append(el('div', 'position:absolute;inset:0;background:radial-gradient(1100px 700px at 78% 40%,rgba(246,209,14,0.07),transparent 70%)'));

  // The right: a scene, the cones in the admin menu, placing, and the style picker's tapes, with
  // tape across the corner. The picker is its panel cut out of the in-game screenshot.
  a.append(card(ingame('scene'), 'left:1010px;top:58px;width:720px;height:405px'));
  a.append(card(adminShot('holders'), 'left:1000px;top:392px;width:420px;height:340px'));
  a.append(card(ingame('placing'), 'left:1330px;top:470px;width:440px;height:248px'));
  a.append(cropCard(ingame('picker'), [1511, 32, 394, 1032], 1652, 96, 240));
  // Tape crossed over the corners, a few styles, the way it goes up at a scene: [id, length,
  // height, angle, position before turning (about its centre)].
  const tapes: [string, number, number, number, string][] = [
    ['crime_scene', 1300, 54, 9, 'left:1080px;top:-6px'],
    ['lspd_line', 900, 46, 34, 'left:1350px;top:37px'],
    ['de_polizei', 1300, 48, -7, 'left:1000px;top:764px'],
    ['police_line_bold', 1500, 62, -14, 'left:1040px;top:610px'],
    ['lsfd_line', 1000, 50, -46, 'left:1260px;top:695px'],
  ];
  for (const [id, w, h, angle, css] of tapes) a.append(await laid(byId.get(id)!, w, h, angle, css));

  const left = el('div', 'position:absolute;left:96px;top:66px;width:820px');
  const logo = el('div', 'display:flex;align-items:center;gap:22px');
  const icon = el('div', `width:82px;height:82px;border-radius:18px;border:3px solid ${YELLOW};display:flex;align-items:center;justify-content:center;background:rgba(246,209,14,0.06)`);
  icon.append(el('img', 'width:64px;height:64px;object-fit:contain'));
  (icon.firstChild as HTMLImageElement).src = ROLL;
  logo.append(icon, el('span', 'font-size:50px;font-weight:700;letter-spacing:-0.02em;color:#fff', ['sd-policetape']));
  left.append(logo);
  left.append(el('div', 'height:2px;margin:36px 0 0;width:760px;background:rgba(255,255,255,0.16)'));
  const eyebrow = el('div', 'display:flex;align-items:center;gap:24px;margin-top:46px');
  eyebrow.append(el('span', `width:64px;height:8px;border-radius:4px;background:${YELLOW}`), el('span', `font-size:29px;font-weight:700;letter-spacing:0.3em;color:${YELLOW}`, ['FIVEM RESOURCE']));
  left.append(eyebrow);
  const h1 = el('div', 'margin-top:40px;font-weight:900;letter-spacing:-0.045em;line-height:0.94');
  const l1 = el('div', 'font-size:132px;color:#fff;white-space:nowrap', ['POLICE TAPE.']);
  const l2 = el('div', `font-size:132px;color:${YELLOW};white-space:nowrap`, ['FOR FIVEM.']);
  h1.append(l1, l2);
  left.append(h1);
  left.append(el('div', 'margin-top:44px;font-size:36px;color:#d7d9de', ['Tape that sags, sways and snaps.']));
  a.append(left);
  a.append(el('div', 'position:absolute;left:96px;bottom:64px;font-size:25px;font-weight:600;letter-spacing:0.2em;color:#9aa0aa;white-space:pre', ['100 STYLES  /  21 POSTS & CONES  /  A TAPE STUDIO']));

  // The headline fits beside the pictures: narrowed together until it does.
  await document.fonts.ready;
  for (let px = 132; px > 80 && l1.scrollWidth > 800; px -= 2) {
    l1.style.fontSize = `${px}px`;
    l2.style.fontSize = `${px}px`;
  }
}

// -- hero: the styles, crossed like tape at a scene --------------------------------------------------
async function hero(): Promise<void> {
  const a = art(1920, 720, 'background:#0b0d10');
  a.append(el('div', `position:absolute;inset:-30px;background:url("${ingame('scene')}") center 58%/cover;filter:blur(7px) brightness(0.32) saturate(0.8)`));
  a.append(el('div', 'position:absolute;inset:0;background:radial-gradient(1200px 520px at 50% 50%,transparent,rgba(0,0,0,0.55))'));
  const laidOut: [string, number, number, string][] = [
    ['crime_scene', 76, -11, 'left:-200px;top:84px'],
    ['police_line_bold', 70, 7, 'left:-200px;top:180px'],
    ['fib_line', 58, -4, 'left:-200px;top:296px'],
    ['lsfd_line', 62, 13, 'left:-200px;top:330px'],
    ['hazmat', 64, -8, 'left:-200px;top:430px'],
    ['triage_immediate', 54, 3, 'left:-200px;top:520px'],
    ['de_polizei', 58, -15, 'left:-200px;top:580px'],
    ['barrier_checker_blue', 46, 10, 'left:-200px;top:610px'],
    ['lspd_line', 60, -2, 'left:-200px;top:30px'],
  ];
  for (const [id, h, angle, css] of laidOut) a.append(await laid(byId.get(id)!, 2400, h, angle, css));
}

// -- every style of a category ---------------------------------------------------------------------
async function sheet(category: string): Promise<void> {
  const name = CATEGORIES.find(([c]) => c === category)?.[1] ?? category;
  const list = STYLES.filter((s) => s.category === category);
  const a = art(1920, null, 'padding:52px 64px 60px;box-sizing:border-box');
  const head = el('div', 'display:flex;align-items:baseline;gap:16px;margin-bottom:34px');
  head.append(el('span', `width:46px;height:8px;border-radius:4px;background:${YELLOW};align-self:center`));
  head.append(el('span', 'font-size:36px;font-weight:700;letter-spacing:-0.01em', [name]), el('span', 'font-size:26px;font-weight:500;color:#6e6e76', [String(list.length)]));
  a.append(head);
  // Three to a row at this height is one whole repeat of the print per style.
  const g = el('div', 'display:grid;grid-template-columns:repeat(3,1fr);gap:26px 40px');
  const w = (1920 - 128 - 2 * 40) / 3;
  for (const s of list) {
    const item = el('div');
    const row = el('div', 'display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-bottom:12px');
    row.append(el('span', 'font-size:22px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis', [s.label]));
    if (s.region) row.append(el('span', 'font-size:18px;font-weight:600;color:#6e6e76', [s.region]));
    item.append(row);
    const box = el('div', 'border-radius:5px;overflow:hidden;box-shadow:0 0 0 1px rgba(255,255,255,0.07)');
    box.append(await strip(s, w, 35));
    item.append(box);
    g.append(item);
  }
  a.append(g);
}

// -- the post and the cones ------------------------------------------------------------------------
async function holders(): Promise<void> {
  const a = art(1920, null, 'padding:52px 64px 60px;box-sizing:border-box');
  const head = el('div', 'display:flex;align-items:baseline;gap:16px;margin-bottom:34px');
  head.append(el('span', `width:46px;height:8px;border-radius:4px;background:${YELLOW};align-self:center`));
  head.append(el('span', 'font-size:36px;font-weight:700', ['Posts and cones']), el('span', 'font-size:26px;font-weight:500;color:#6e6e76', [String(HOLDERS.length)]));
  a.append(head);
  const g = el('div', 'display:grid;grid-template-columns:repeat(7,1fr);gap:20px');
  for (const [id, label, h] of HOLDERS) {
    const tile = el('div', 'border-radius:12px;padding:10px;background:#17181c;border:1px solid rgba(255,255,255,0.08)');
    const img = el('img', 'display:block;width:100%;aspect-ratio:1/1;object-fit:contain;border-radius:8px;background:radial-gradient(circle at 50% 38%,rgba(255,255,255,0.08),rgba(255,255,255,0) 70%),#0f1013');
    img.src = holderPic(id);
    tile.append(img);
    tile.append(el('div', 'margin-top:10px;padding:0 2px;font-size:17px;font-weight:600;line-height:1.25;min-height:2.5em', [label]));
    tile.append(el('div', 'margin-top:4px;padding:0 2px;font-size:15px;font-weight:500;color:#5b5b63', [heightLabel(h)]));
    g.append(tile);
  }
  a.append(g);
  await Promise.all([...a.querySelectorAll('img')].map((i) => (i.complete ? null : new Promise((r) => (i.onload = r)))));
}

async function main(): Promise<void> {
  const view = location.hash.slice(1) || 'banner';
  if (view === 'banner') await banner();
  else if (view === 'hero') await hero();
  else if (view === 'holders') await holders();
  else if (view.startsWith('styles-')) await sheet(view.slice(7));
  await document.fonts.ready;
  document.body.dataset.ready = '1';
}

window.addEventListener('hashchange', () => location.reload());
void main();
