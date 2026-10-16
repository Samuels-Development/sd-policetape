// A length of tape on screen: the style's repeat painted once at this height, laid end to end,
// with a torn end or two. `peel` (0..1) tears it away from the left, for hold-to-remove.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { paintTape, prepare } from '../paint/tape';
import { TILE_W, TILE_H, type Style } from '../paint/types';

const tileCache = new Map<string, HTMLCanvasElement>();
const ASPECT = TILE_W / TILE_H;

function tileFor(style: Style, h: number, fontsReady: boolean): HTMLCanvasElement {
  const key = `${h}|${JSON.stringify(style)}`;
  const hit = tileCache.get(key);
  if (hit) return hit;
  const tile = document.createElement('canvas');
  tile.height = h;
  tile.width = Math.round(h * ASPECT);
  paintTape(tile.getContext('2d')!, style, tile.width, tile.height);
  // A tile painted before its face arrived is not worth keeping.
  if (fontsReady) {
    if (tileCache.size > 400) tileCache.clear();
    tileCache.set(key, tile);
  }
  return tile;
}

/** A ragged edge, as a list of x offsets in px at even steps down the strip. Fixed, so it never flickers. */
const RAG = [3, 0, 5, 1, 4, 0, 6, 2, 4];

function edge(x: (offset: number) => string, top: boolean): string {
  const pts = RAG.map((o, i) => `${x(o)} ${(i / (RAG.length - 1)) * 100}%`);
  return (top ? pts : pts.reverse()).join(', ');
}

export function tornPath(left: boolean, right: boolean, peel = 0): string | undefined {
  if (!left && !right && peel <= 0) return undefined;
  const p = Math.max(0, Math.min(1, peel)) * 100;
  const l = left || peel > 0 ? edge((o) => `calc(${p}% + ${o}px)`, false) : `${p}% 100%, ${p}% 0%`;
  const r = right ? edge((o) => `calc(100% - ${o}px)`, true) : '100% 0%, 100% 100%';
  return `polygon(${l}, ${r})`;
}

interface Props {
  style: Style;
  height: number;
  className?: string;
  tornLeft?: boolean;
  tornRight?: boolean;
  peel?: number;
  /** Slides the print along, in tile widths, so a strip can be seen moving. */
  offset?: number;
}

export function TapeStrip({ style, height, className, tornLeft = false, tornRight = false, peel = 0, offset = 0 }: Props) {
  const wrap = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [width, setWidth] = useState(0);
  const [ready, setReady] = useState(0);

  useLayoutEffect(() => {
    const el = wrap.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const ro = new ResizeObserver(() => setWidth(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    let live = true;
    void prepare(style).then(() => {
      if (live) setReady((n) => n + 1);
    });
    return () => {
      live = false;
    };
  }, [style]);

  useEffect(() => {
    const c = canvas.current;
    if (!c || width <= 0) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const h = Math.round(height * dpr);
    c.width = Math.round(width * dpr);
    c.height = h;
    const ctx = c.getContext('2d')!;
    const tile = tileFor(style, h, ready > 0);
    const shift = -(((offset % 1) + 1) % 1) * tile.width;
    for (let x = shift; x < c.width; x += tile.width) ctx.drawImage(tile, Math.round(x), 0);
  }, [style, width, height, ready, offset]);

  return (
    <div
      ref={wrap}
      className={className}
      style={{ height, clipPath: tornPath(tornLeft, tornRight, peel), WebkitClipPath: tornPath(tornLeft, tornRight, peel) }}
    >
      <canvas ref={canvas} style={{ width: '100%', height: '100%', display: 'block' }} />
    </div>
  );
}
