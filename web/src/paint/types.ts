// A tape style, exactly as shared/schema.lua normalises it: every optional part is present or
// `false`, so nothing here has to invent a default. configs/styles.lua documents the fields.

export type PatternType = 'diagonal' | 'blocks' | 'checker' | 'chevron' | 'band' | 'dashes' | 'dots' | 'zigzag' | 'lines';
export type EdgeStyle = 'solid' | 'double' | 'dashed' | 'checker';
export type Fade = 'gradient' | 'split';
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

// The fields marked optional came after the first styles were saved: the schema always sets them,
// and the painter reads a missing one as the way tape looked before it existed.

export interface Pattern {
  type: PatternType;
  color: string;
  size: number;
  angle: number;
  /** 0.1..1 */
  opacity?: number;
  /** How much of each period is printed, 0.15..0.85 (stripes, blocks, chevrons, dashes, dots, zigzag, lines). */
  fill?: number;
}

export interface Edges {
  color: string;
  size: number;
  style?: EdgeStyle;
  /** A gap of base colour between the band and the tape's edge, in tape widths. */
  inset?: number;
}

export interface TapeText {
  items: string[];
  color: string;
  /** Every other piece of wording in this colour. */
  altColor?: string | false;
  font: FontKey;
  size: number;
  spacing: number;
  /** Letters narrower (< 1) or wider (> 1) than the face draws them. */
  width?: number;
  /** Up (-) or down (+) from the middle of the tape, in tape widths. */
  offset?: number;
  italic: boolean;
  plate: false | { color: string; padding: number; radius?: number };
  outline: false | { color: string; width: number };
  shadow?: false | { color: string; distance: number };
  separator: Separator;
  separatorColor: string | false;
  separatorSize?: number;
  repeats: number;
}

export interface Style {
  id: string;
  label: string;
  category: string;
  region: string | false;
  base: string;
  /** A second background colour: top to bottom, or the tape split in two. */
  base2?: false | { color: string; mode: Fade };
  pattern: false | Pattern;
  edges: false | Edges;
  text: false | TapeText;
  custom: boolean;
  /** Tape Studio styles: who made it, and a hash of who they are (server/styles.lua authorKey). */
  author?: string | null;
  authorKey?: string | null;
}

/** The printed strip repeats every TILE_W x TILE_H pixels: 16 tape widths long. */
export const TILE_W = 1024;
export const TILE_H = 64;
