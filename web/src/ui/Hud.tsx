// The prompt over the game while placing tape or looking at a tape. Never takes focus: Lua owns
// the keys and sends what they do (client/place.lua, client/look.lua).
import type { Style } from '../paint/types';
import { TapeStrip } from './TapeStrip';

export interface HudKey {
  k: string;
  t: string;
}

export interface HudState {
  mode: 'place' | 'look';
  styleId: string;
  title?: string;
  line?: string;
  lineKind?: 'ok' | 'warn' | 'stop';
  keys: HudKey[];
}

const STATUS = { ok: 'sc-status sc-status--ok', warn: 'sc-status sc-status--warn', stop: 'sc-status sc-status--danger' } as const;

export function Kbd({ k }: { k: string }) {
  return <kbd className="sc-kbd">{k}</kbd>;
}

export function Hud({ hud, style, progress }: { hud: HudState; style: Style; progress: number }) {
  return (
    <div className="pointer-events-none fixed bottom-[6vh] left-1/2 w-[420px] -translate-x-1/2 animate-panelIn">
      <div className="sc-window px-4 pb-3.5 pt-3" style={{ borderRadius: 12 }}>
        <div className="flex items-baseline gap-2.5">
          <span className="sc-title truncate text-[13.5px]">{hud.title ?? style.label}</span>
          {style.region && <span className="sc-subtitle">{style.region}</span>}
        </div>

        <TapeStrip style={style} height={20} className="sc-strip mt-2.5" />

        {progress > 0 && (
          <div className="mt-2 h-[2px] overflow-hidden rounded-full bg-surface3">
            <div className="h-full rounded-full bg-t1" style={{ width: `${Math.min(100, progress * 100)}%` }} />
          </div>
        )}

        {hud.line && <div className={`mt-2.5 ${STATUS[hud.lineKind ?? 'ok']}`}>{hud.line}</div>}

        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2">
          {hud.keys.map((key) => (
            <span key={key.k + key.t} className="inline-flex items-center gap-1.5 text-[12px] text-t2">
              <Kbd k={key.k} />
              {key.t}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}
