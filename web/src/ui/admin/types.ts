// What server/admin.lua sends (client/admin.lua adds street and distance to each tape).

export type Tab = 'tapes' | 'styles' | 'holders' | 'settings';
export const TABS: Tab[] = ['tapes', 'styles', 'holders', 'settings'];

export interface Vec {
  x: number;
  y: number;
  z: number;
}

export interface TapeRow {
  id: number;
  style: string;
  label: string;
  owner?: string | null;
  script: boolean;
  created?: number | null;
  length: number;
  torn: boolean;
  down: boolean;
  a: Vec;
  b: Vec;
  ah?: string | null;
  bh?: string | null;
  street?: string;
  distance?: number;
}

export interface Toggle {
  key: string;
  group: string;
  on: boolean;
  default: boolean;
}

export interface HolderInfo {
  id: string;
  label: string;
  model: string;
  image: string;
  height: number;
}

export interface Snapshot {
  now: number;
  tapes: TapeRow[];
  toggles: Toggle[];
  offStyles: string[];
  offHolders: string[];
  holders: HolderInfo[];
  total: number;
}

export interface ActReply {
  ok: boolean;
  message?: string;
  snapshot?: Snapshot;
}
