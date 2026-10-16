// Which posts and cones players may stand on open ground: a tile with its picture for each, ticked
// while it is available (sd-computers' prop tiles). One switched off can no longer be put up; ones
// already standing stay, and tape can still be tied to them.
import { Check } from 'lucide-react';
import { heightLabel } from '../Holders';
import { useT } from '../locale';
import { act } from './api';
import { ScrollArea } from './ScrollArea';
import { Heading, Hint } from './shared';
import { useAdmin } from './store';
import type { HolderInfo } from './types';

export function HoldersTab() {
  const t = useT();
  const snapshot = useAdmin((s) => s.snapshot)!;
  const busy = useAdmin((s) => s.busy);
  const off = new Set(snapshot.offHolders);
  const holders = snapshot.holders;
  const onCount = holders.filter((h) => !off.has(h.id)).length;

  function allOff() {
    // Something has to be left: the first one that is on stays.
    const keep = holders.find((h) => !off.has(h.id));
    const ids = holders.filter((h) => h !== keep && !off.has(h.id)).map((h) => h.id);
    if (ids.length) void act('holders', { ids, on: false }, t('admin.holders.toast_all_off'));
  }

  return (
    <ScrollArea className="h-full" viewClassName="flex flex-col gap-4 px-6 py-5">
      <Heading title={t('admin.holders.title')} count={holders.length}>
        <span className="mono mr-1 text-[11.5px]" style={{ color: 'var(--text-3)' }}>
          {t('admin.holders.available', { on: onCount, total: holders.length })}
        </span>
        <button
          type="button"
          className="sc-btn"
          disabled={busy || onCount === holders.length}
          onClick={() => void act('holders', { ids: holders.map((h) => h.id), on: true }, t('admin.holders.toast_all_on'))}
        >
          {t('admin.holders.all_on')}
        </button>
        <button type="button" className="sc-btn" disabled={busy || onCount <= 1} onClick={allOff}>
          {t('admin.holders.all_off')}
        </button>
      </Heading>
      <Hint className="-mt-2">{t('admin.holders.hint')}</Hint>

      <div className="grid flex-shrink-0 grid-cols-6 gap-2">
        {holders.map((h) => (
          <Tile
            key={h.id}
            h={h}
            on={!off.has(h.id)}
            disabled={busy || (!off.has(h.id) && onCount <= 1)}
            onToggle={(on) => void act('holders', { ids: [h.id], on }, t(on ? 'admin.holders.toast_on' : 'admin.holders.toast_off', { name: h.label }))}
          />
        ))}
      </div>
    </ScrollArea>
  );
}

function Tile({ h, on, disabled, onToggle }: { h: HolderInfo; on: boolean; disabled: boolean; onToggle(on: boolean): void }) {
  const t = useT();
  return (
    <div
      className="relative flex flex-col rounded-[8px] p-1.5 transition-colors"
      style={{ background: on ? 'var(--surface-3)' : 'var(--surface-2)', border: `1px solid ${on ? 'var(--hairline-focus)' : 'var(--hairline)'}` }}
    >
      <button type="button" aria-pressed={on} title={h.model} disabled={disabled} onClick={() => onToggle(!on)} className="flex min-w-0 flex-col border-0 bg-transparent p-0 text-left">
        <img src={h.image} alt="" draggable={false} className="sc-pic" style={{ filter: on ? undefined : 'grayscale(1) brightness(0.6)' }} />
        <span className="mt-1.5 block w-full truncate px-0.5 text-[11.5px] font-medium" style={{ color: on ? 'var(--text-1)' : 'var(--text-3)' }}>
          {h.label}
        </span>
        <span className="mono block w-full truncate px-0.5 text-[10.5px]" style={{ color: 'var(--text-4)' }}>
          {t('admin.holders.tall', { height: heightLabel(h.height) })}
        </span>
      </button>
      {on && (
        <span className="pointer-events-none absolute right-2.5 top-2.5 flex h-4 w-4 items-center justify-center rounded-full" style={{ background: 'var(--text-1)', color: '#0c0d0f' }}>
          <Check size={11} strokeWidth={3} />
        </span>
      )}
    </div>
  );
}
