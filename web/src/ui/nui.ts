// Talking to client/nui.lua. In a plain browser (npm run dev) there is no game: posts are logged
// and src/ui/dev.ts plays the game's part.
import { useEffect, useRef } from 'react';

export const inGame = typeof (window as unknown as { invokeNative?: unknown }).invokeNative === 'function';

const resource = inGame
  ? ((window as unknown as { GetParentResourceName?: () => string }).GetParentResourceName?.() ?? 'sd-policetape')
  : 'sd-policetape';

export async function post<T = unknown>(name: string, data: unknown = {}): Promise<T | null> {
  if (!inGame) {
    console.info('[nui post]', name, data);
    return null;
  }
  try {
    const res = await fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    });
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export type Handler = (msg: Record<string, unknown>) => void;

/** Calls `handler` for every message Lua sends, with the latest handler (no stale closures). */
export function useNuiMessages(handler: Handler): void {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    const listener = (e: MessageEvent) => {
      if (e.data && typeof e.data === 'object' && typeof e.data.action === 'string') ref.current(e.data);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, []);
}

/** Readable ink on a background colour: the darker of two inks unless the background is dark. */
export function inkFor(hex: string): string {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  const l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return l > 0.55 ? '#14171B' : '#F4F6F8';
}
