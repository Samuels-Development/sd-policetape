// Words come from locales/<lang>.json through Lua (its "ui" part). English is bundled as the
// fallback for any key a translation lacks, and for the browser preview.
import { createContext, useContext } from 'react';
import en from '../../../locales/en.json';

export type Dict = Record<string, unknown>;

export const fallback: Dict = en.ui as Dict;

function lookup(dict: Dict, key: string): string | undefined {
  let node: unknown = dict;
  for (const part of key.split('.')) {
    if (!node || typeof node !== 'object') return undefined;
    node = (node as Dict)[part];
  }
  return typeof node === 'string' ? node : undefined;
}

export type T = (key: string, vars?: Record<string, string | number>) => string;

export function makeT(dict: Dict): T {
  return (key, vars) => {
    let s = lookup(dict, key) ?? lookup(fallback, key) ?? key;
    if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v));
    return s;
  };
}

export const LocaleContext = createContext<T>(makeT(fallback));
export const useT = (): T => useContext(LocaleContext);
