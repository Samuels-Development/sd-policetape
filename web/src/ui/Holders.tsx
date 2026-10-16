// The holder menu: the post or cone a new end of tape stands on, with a picture of each. A panel
// down the right like the style picker, so the scene stays in view; the one under the pointer is
// the ghost in the world while it is open (holdersHover).
import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, Search, X } from 'lucide-react';
import { useT } from './locale';
import { post } from './nui';

export interface HolderCard {
  id: string;
  label: string;
  image: string;
  height: number;
}

const COLS = 3;

export function heightLabel(m: number): string {
  return m >= 1 ? `${m.toFixed(2)} m` : `${Math.round(m * 100)} cm`;
}

interface Props {
  list: HolderCard[];
  selected: string;
  onClose: () => void;
}

export function Holders({ list, selected, onClose }: Props) {
  const t = useT();
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(selected);
  const search = useRef<HTMLInputElement>(null);
  const grid = useRef<HTMLDivElement>(null);

  useEffect(() => {
    search.current?.focus();
    grid.current?.querySelector(`[data-id="${selected}"]`)?.scrollIntoView({ block: 'center' });
  }, [selected]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? list.filter((h) => `${h.label} ${h.id}`.toLowerCase().includes(q)) : list;
  }, [list, query]);

  const focus = list.find((h) => h.id === active) ?? list.find((h) => h.id === selected) ?? list[0];

  function hover(id: string) {
    if (id === active) return;
    setActive(id);
    void post('holdersHover', { id });
  }

  function choose(id: string) {
    void post('holdersChoose', { id });
  }

  function onKey(e: React.KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
      return;
    }
    // (left and right move the caret while there is something typed)
    if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && query) return;
    const steps: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: COLS, ArrowUp: -COLS };
    const idx = shown.findIndex((h) => h.id === active);
    if (steps[e.key]) {
      e.preventDefault();
      const next = shown[Math.max(0, Math.min(shown.length - 1, idx < 0 ? 0 : idx + steps[e.key]))];
      if (next) {
        hover(next.id);
        grid.current?.querySelector(`[data-id="${next.id}"]`)?.scrollIntoView({ block: 'nearest' });
      }
    } else if (e.key === 'Enter' && idx >= 0) {
      e.preventDefault();
      choose(shown[idx].id);
    }
  }

  return (
    <aside onKeyDown={onKey} className="sc-window fixed bottom-3 right-3 top-3 w-[400px] animate-drawerIn">
      <div className="sc-window__head">
        <div className="flex min-w-0 items-baseline gap-2.5">
          <span className="sc-title">{t('holders.title')}</span>
          <span className="sc-subtitle">{t('holders.count', { count: list.length })}</span>
        </div>
        <button type="button" className="sc-btn sc-btn--icon ml-auto" onClick={onClose} aria-label={t('holders.close')}>
          <X size={16} />
        </button>
      </div>

      {focus && (
        <div className="px-4">
          <div className="sc-card flex items-center gap-3.5 p-2.5 pr-3.5">
            <img src={focus.image} alt="" draggable={false} className="sc-pic flex-none" style={{ width: 84 }} />
            <div className="min-w-0">
              <div className="text-[13px] font-semibold leading-snug text-t1">{focus.label}</div>
              <div className="sc-label mt-1">{t('holders.tall', { height: heightLabel(focus.height) })}</div>
            </div>
          </div>
        </div>
      )}

      <div className="mt-3 px-4">
        <div className="sc-search">
          <Search size={14} />
          <input ref={search} value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('holders.search')} className="sc-input" />
        </div>
      </div>

      <div ref={grid} className="scroll mt-3 min-h-0 flex-1 overflow-y-auto border-t border-hairline px-4 pb-4 pt-3">
        {shown.length === 0 && <p className="py-6 text-[13px] text-t3">{t('holders.empty', { query })}</p>}
        <div className="grid grid-cols-3 gap-2">
          {shown.map((h) => {
            const on = h.id === active;
            return (
              <button
                key={h.id}
                type="button"
                data-id={h.id}
                onMouseEnter={() => hover(h.id)}
                onFocus={() => hover(h.id)}
                onClick={() => choose(h.id)}
                className="relative flex min-w-0 flex-col rounded-[8px] p-1.5 text-left transition-colors"
                style={{ background: on ? 'var(--surface-3)' : 'var(--surface-2)', border: `1px solid ${on ? 'var(--hairline-focus)' : 'var(--hairline)'}` }}
              >
                <img src={h.image} alt="" draggable={false} className="sc-pic" />
                <span className="mt-1.5 line-clamp-2 min-h-[2.5em] w-full px-0.5 text-[11.5px] font-medium leading-tight" style={{ color: on ? 'var(--text-1)' : 'var(--text-2)' }}>
                  {h.label}
                </span>
                <span className="mono mt-0.5 block w-full px-0.5 text-[10.5px]" style={{ color: 'var(--text-4)' }}>
                  {heightLabel(h.height)}
                </span>
                {h.id === selected && (
                  <span className="pointer-events-none absolute right-2.5 top-2.5 flex h-4 w-4 items-center justify-center rounded-full" style={{ background: 'var(--text-1)', color: '#0c0d0f' }}>
                    <Check size={11} strokeWidth={3} />
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      <div className="flex h-14 shrink-0 items-center gap-3 border-t border-hairline px-4">
        <span className="flex min-w-0 items-center gap-1.5 text-[11.5px] text-t3">
          <kbd className="sc-kbd">←</kbd>
          <kbd className="sc-kbd">→</kbd>
          <span className="mr-2">{t('holders.choose')}</span>
          <kbd className="sc-kbd">Enter</kbd>
          <span className="mr-2">{t('holders.use')}</span>
          <kbd className="sc-kbd">Esc</kbd>
          <span>{t('holders.exit')}</span>
        </span>
      </div>
    </aside>
  );
}
