// A tape style, exactly as shared/schema.lua normalises it: every optional part is present or
// `false`, so nothing here has to invent a default. configs/styles.lua documents the fields.

export type PatternType = 'diagonal' | 'blocks' | 'checker' | 'chevron' | 'band' | 'dashes';
export type Separator = 'none' | 'dot' | 'star' | 'bar' | 'slash' | 'diamond' | 'cross' | 'chevron';
export type FontKey =
  | 'oswald'
  | 'anton'
  | 'bebas'
  | 'barlow'
  | 'roboto'
  | 'teko'
  | 'stencil'
  | 'archivo'
  | 'russo'
  | 'staatliches'
  | 'blackops';

export interface Pattern {
  type: PatternType;
  color: string;
  size: number;
  angle: number;
}

export interface Edges {
  color: string;
  size: number;
}

export interface TapeText {
  items: string[];
  color: string;
  font: FontKey;
  size: number;
  spacing: number;
  italic: boolean;
  plate: false | { color: string; padding: number };
  outline: false | { color: string; width: number };
  separator: Separator;
  separatorColor: string | false;
  repeats: number;
}

export interface Style {
  id: string;
  label: string;
  category: string;
  region: string | false;
  base: string;
  pattern: false | Pattern;
  edges: false | Edges;
  text: false | TapeText;
  custom: boolean;
}

/** The printed strip repeats every TILE_W x TILE_H pixels: 16 tape widths long. */
export const TILE_W = 1024;
export const TILE_H = 64;
