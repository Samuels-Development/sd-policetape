// Talking to client/admin.lua. Every action is one call; the reply carries a fresh snapshot (and,
// for a toast, a message). In a plain browser (npm run dev) src/ui/dev.ts answers instead.
import { inGame, post } from '../nui';
import { get, set, setSnapshot, toast, tr } from './store';
import type { ActReply, Snapshot } from './types';

async function send(verb: string, data: Record<string, unknown>): Promise<ActReply | null> {
  if (!inGame && import.meta.env.DEV) return (await import('../dev')).adminAct(verb, data);
  return post<ActReply>('adminAct', { verb, data });
}

/** Runs `verb` on the server. `okText` is the toast when it works and the server says nothing. */
export async function act(verb: string, data: Record<string, unknown>, okText?: string): Promise<boolean> {
  set({ busy: true });
  const res = await send(verb, data);
  set({ busy: false });
  if (!res) {
    toast(tr('admin.common.failed'), false);
    return false;
  }
  if (res.snapshot) setSnapshot(res.snapshot);
  if (res.ok) {
    const text = res.message || okText;
    if (text) toast(text, true);
  } else {
    toast(res.message || tr('admin.common.failed'), false);
  }
  return res.ok === true;
}

/** A fresh snapshot, unless something is on its way already. */
export async function refresh(): Promise<void> {
  if (get().busy || !inGame) return;
  const s = await post<Snapshot | false>('adminRefresh');
  if (s) setSnapshot(s);
}

export function close(): void {
  void post('adminClose');
}

export function teleport(id: number): void {
  void post('adminTeleport', { id });
}

export function waypoint(id: number): void {
  void post('adminWaypoint', { id });
}
