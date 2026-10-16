// The admin menu's state, shaped like sd-computers' zustand store (snapshot, tab, busy, toasts)
// on a store of our own: React's useSyncExternalStore and nothing else, so no new dependency.
import { useSyncExternalStore } from 'react';
import type { T } from '../locale';
import { TABS, type Snapshot, type Tab } from './types';

export interface Toast {
  id: number;
  text: string;
  ok: boolean;
}

interface State {
  snapshot: Snapshot | null;
  tab: Tab;
  busy: boolean;
  toasts: Toast[];
}

const TAB_KEY = 'sd_policetape:adminTab';

function savedTab(): Tab {
  try {
    const v = localStorage.getItem(TAB_KEY) as Tab | null;
    return v && TABS.includes(v) ? v : 'tapes';
  } catch {
    return 'tapes';
  }
}

let state: State = { snapshot: null, tab: savedTab(), busy: false, toasts: [] };
const listeners = new Set<() => void>();

export function get(): State {
  return state;
}

export function set(patch: Partial<State> | ((s: State) => Partial<State>)): void {
  state = { ...state, ...(typeof patch === 'function' ? patch(state) : patch) };
  listeners.forEach((l) => l());
}

function subscribe(l: () => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

/** The part of the state `pick` returns; re-renders only when that changes. */
export function useAdmin<R>(pick: (s: State) => R): R {
  return useSyncExternalStore(subscribe, () => pick(state));
}

// An empty Lua table has no way to say it was a list: it can arrive as {} instead of []. Every
// list in a snapshot is made a list here, once.
const list = <V>(v: unknown): V[] => (Array.isArray(v) ? (v as V[]) : []);

export function setSnapshot(s: Snapshot | null | undefined): void {
  if (!s || typeof s !== 'object') return;
  set({
    snapshot: {
      ...s,
      tapes: list(s.tapes),
      toggles: list(s.toggles),
      offStyles: list(s.offStyles),
      offHolders: list(s.offHolders),
      holders: list(s.holders),
    },
  });
}

export function setTab(tab: Tab): void {
  try {
    localStorage.setItem(TAB_KEY, tab);
  } catch {
    /* (a page without storage just forgets) */
  }
  set({ tab });
}

let nextToast = 1;
export function toast(text: string, ok = true, ms = 2600): void {
  const id = nextToast++;
  set((s) => ({ toasts: [...s.toasts, { id, text, ok }].slice(-3) }));
  window.setTimeout(() => set((s) => ({ toasts: s.toasts.filter((x) => x.id !== id) })), ms);
}

// The words for what is said outside a component (toasts from api.ts): the panel hands its own
// translator over each time it renders.
let words: T = (key) => key;
export function setWords(t: T): void {
  words = t;
}
export function tr(key: string, vars?: Record<string, string | number>): string {
  return words(key, vars);
}
