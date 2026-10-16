// The style picker: a panel down the right of the screen, so the scene stays in view. While
// placing, the style under the pointer is also what the tape in the world turns into
// (pickerHover).
import { useEffect, useMemo, useRef, useState } from 'react';
import { Plus, Search, X } from 'lucide-react';
import type { Style } from '../paint/types';
import { useT } from './locale';
import { post } from './nui';
import { TapeStrip } from './TapeStrip';

const ORDER = ['police', 'federal', 'crime', 'fire', 'ems', 'hazard', 'utility', 'plain', 'international', 'custom'];

interface Props {
  styles: Style[];
  selected: string;
  canStudio: boolean;
  onHover: (id: string) => void;
  onClose: () => void;
  onOpenStudio: () => void;
}

export function Picker({ styles, selected, canStudio, onHover, onClose, onOpenStudio }: Props) {
  const t = useT();
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('all');
  const [active, setActive] = useState(selected);
  const search = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);

  useEffect(() => {
    search.current?.focus();
    list.current?.querySelector(`[data-id="${selected}"]`)?.scrollIntoView({ block: 'center' });
  }, [selected]);

  const counts = useMemo(() => {
    const c: Record<string, number> = { all: styles.length };
    for (const s of styles) c[s.category] = (c[s.category] ?? 0) + 1;
    return c;
  }, [styles]);
  const categories = useMemo(() => ORDER.filter((c) => counts[c]), [counts]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return styles.filter((s) => {
      if (category !== 'all' && s.category !== category) return false;
      if (!q) return true;
      const words = s.text ? s.text.items.join(' ') : '';
      return `${s.label} ${s.region || ''} ${words} ${t(`categories.${s.category}`)}`.toLowerCase().includes(q);
    });
  }, [styles, query, category, t]);

  const groups = useMemo(() => {
    const out: { cat: string; items: Style[] }[] = [];
    for (const cat of ORDER) {
      const items = shown.filter((s) => s.category === cat);
      if (items.length) out.push({ cat, items });
    }
    return out;
  }, [shown]);

  const focus = styles.find((s) => s.id === active) ?? styles.find((s) => s.id === selected) ?? styles[0];

  function hover(id: string) {
    if (id === active) return;
    setActive(id);
    onHover(id);
  }

  function choose(id: string) {
    void post('pickerChoose', { id });
  }

  function onKey(e: React.KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
      return;
    }
    const idx = shown.findIndex((s) => s.id === active);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const next = shown[Math.max(0, Math.min(shown.length - 1, idx + (e.key === 'ArrowDown' ? 1 : -1)))];
      if (next) {
        hover(next.id);
        list.current?.querySelector(`[data-id="${next.id}"]`)?.scrollIntoView({ block: 'nearest' });
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
          <span className="sc-title">{t('picker.title')}</span>
          <span className="sc-subtitle">{t('picker.count', { count: styles.length })}</span>
        </div>
        <button type="button" className="sc-btn sc-btn--icon ml-auto" onClick={onClose} aria-label={t('picker.close')}>
          <X size={16} />
        </button>
      </div>

      {focus && (
        <div className="px-4">
          <div className="sc-card px-3.5 pb-3.5 pt-3">
            <div className="flex items-baseline justify-between gap-3">
              <span className="truncate text-[13px] font-semibold text-t1">{focus.label}</span>
              <span className="sc-label shrink-0">
                {t(`categories.${focus.category}`)}
                {focus.region ? `, ${focus.region}` : ''}
              </span>
            </div>
            <TapeStrip style={focus} height={30} className="sc-strip mt-2.5" />
          </div>
        </div>
      )}

      <div className="mt-3 px-4">
        <div className="sc-search">
          <Search size={14} />
          <input ref={search} value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('picker.search')} className="sc-input" />
        </div>
      </div>

      <div className="sc-chips border-b border-hairline px-4 pb-3 pt-3">
        {['all', ...categories].map((c) => (
          <button key={c} type="button" className="sc-chip" data-on={category === c} onClick={() => setCategory(c)}>
            {t(`categories.${c}`)}
            <span className="sc-chip__count">{counts[c]}</span>
          </button>
        ))}
      </div>

      <div ref={list} className="scroll min-h-0 flex-1 overflow-y-auto px-4 pb-4">
        {groups.length === 0 && <p className="py-6 text-[13px] text-t3">{t('picker.empty', { query })}</p>}
        {groups.map((g) => (
          <section key={g.cat} className="mt-4">
            {category === 'all' && (
              <h2 className="sc-heading mb-2">
                {t(`categories.${g.cat}`)}
                <span className="sc-heading__count">{g.items.length}</span>
              </h2>
            )}
            <div className="sc-list">
              {g.items.map((s) => (
                <button
                  key={s.id}
                  type="button"
                  data-id={s.id}
                  data-on={s.id === active}
                  onMouseEnter={() => hover(s.id)}
                  onFocus={() => hover(s.id)}
                  onClick={() => choose(s.id)}
                  className="sc-row"
                >
                  <span className="flex items-baseline justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-2 truncate text-[13px] font-medium text-t1">
                      {s.label}
                      {s.id === selected && <span className="sc-status sc-status--ok" />}
                    </span>
                    {s.region && <span className="sc-label">{s.region}</span>}
                  </span>
                  <TapeStrip style={s} height={14} className="sc-strip mt-2" />
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>

      <div className="flex h-14 shrink-0 items-center gap-3 border-t border-hairline px-4">
        <span className="flex min-w-0 items-center gap-1.5 text-[11.5px] text-t3">
          <kbd className="sc-kbd">↑</kbd>
          <kbd className="sc-kbd">↓</kbd>
          <span className="mr-2">{t('picker.choose')}</span>
          <kbd className="sc-kbd">Enter</kbd>
          <span className="mr-2">{t('picker.use')}</span>
          <kbd className="sc-kbd">Esc</kbd>
          <span>{t('picker.exit')}</span>
        </span>
        {canStudio && (
          <button type="button" className="sc-btn ml-auto" onClick={onOpenStudio}>
            <Plus size={14} />
            {t('picker.new_style')}
          </button>
        )}
      </div>
    </aside>
  );
}
