// Which tape styles players may put up: a switch for each, and for each category at once. One
// switched off is left out of the style picker for everyone; tape already up in it stays.
import { useMemo, useState } from 'react';
import type { Style } from '../../paint/types';
import { useT } from '../locale';
import { TapeStrip } from '../TapeStrip';
import { act } from './api';
import { ScrollArea } from './ScrollArea';
import { Badge, Empty, Heading, Hint, SearchInput, Switch } from './shared';
import { useAdmin } from './store';

const ORDER = ['police', 'federal', 'crime', 'fire', 'ems', 'hazard', 'utility', 'plain', 'international', 'custom'];

type Filter = 'all' | 'on' | 'off';

export function StylesTab({ styles }: { styles: Style[] }) {
  const t = useT();
  const snapshot = useAdmin((s) => s.snapshot)!;
  const busy = useAdmin((s) => s.busy);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('all');

  const off = useMemo(() => new Set(snapshot.offStyles), [snapshot.offStyles]);
  const onCount = styles.filter((s) => !off.has(s.id)).length;

  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    const shown = styles.filter((s) => {
      if (filter === 'on' && off.has(s.id)) return false;
      if (filter === 'off' && !off.has(s.id)) return false;
      if (!q) return true;
      const words = s.text ? s.text.items.join(' ') : '';
      return `${s.label} ${s.id} ${s.region || ''} ${words} ${t(`categories.${s.category}`)}`.toLowerCase().includes(q);
    });
    const cats = [...ORDER, ...new Set(styles.map((s) => s.category).filter((c) => !ORDER.includes(c)))];
    return cats.map((cat) => ({ cat, items: shown.filter((s) => s.category === cat) })).filter((g) => g.items.length > 0);
  }, [styles, query, filter, off, t]);

  /** Sets `ids` on or off. "All off" keeps the first one that is on, so something is left. */
  function setMany(ids: string[], on: boolean, text: string) {
    let list = ids;
    if (!on) {
      const left = styles.filter((s) => !off.has(s.id) && !ids.includes(s.id));
      if (left.length === 0) {
        const keep = styles.find((s) => !off.has(s.id));
        list = ids.filter((id) => id !== keep?.id);
      }
    }
    if (list.length) void act('styles', { ids: list, on }, text);
  }

  const filters: { id: Filter; label: string }[] = [
    { id: 'all', label: t('admin.styles.filter_all') },
    { id: 'on', label: t('admin.styles.filter_on') },
    { id: 'off', label: t('admin.styles.filter_off') },
  ];

  return (
    <ScrollArea className="h-full" viewClassName="flex flex-col gap-4 px-6 py-5">
      <Heading title={t('admin.styles.title')} count={styles.length}>
        <span className="mono mr-1 text-[11.5px]" style={{ color: 'var(--text-3)' }}>
          {t('admin.styles.available', { on: onCount, total: styles.length })}
        </span>
        <button type="button" className="sc-btn" disabled={busy || onCount === styles.length} onClick={() => setMany(styles.map((s) => s.id), true, t('admin.styles.toast_group_on', { group: t('admin.common.all') }))}>
          {t('admin.styles.all_on')}
        </button>
        <button type="button" className="sc-btn" disabled={busy || onCount <= 1} onClick={() => setMany(styles.map((s) => s.id), false, t('admin.styles.toast_group_off', { group: t('admin.common.all') }))}>
          {t('admin.styles.all_off')}
        </button>
      </Heading>
      <Hint className="-mt-2">{t('admin.styles.hint')}</Hint>

      <div className="flex flex-shrink-0 items-center gap-2">
        <SearchInput value={query} onChange={setQuery} placeholder={t('admin.styles.search')} />
        <div className="sc-segment">
          {filters.map((f) => (
            <button key={f.id} type="button" data-on={filter === f.id} onClick={() => setFilter(f.id)}>
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {groups.length === 0 && <Empty text={t('admin.styles.no_match')} />}
      {groups.map((g) => {
        const all = styles.filter((s) => s.category === g.cat);
        const on = all.filter((s) => !off.has(s.id)).length;
        const name = t(`categories.${g.cat}`);
        return (
          <section key={g.cat} className="flex flex-shrink-0 flex-col gap-2">
            <div className="flex items-center gap-2 px-1">
              <span className="sc-heading">
                {name}
                <span className="sc-heading__count">
                  {on} / {all.length}
                </span>
              </span>
              <div className="ml-auto flex items-center gap-1.5">
                <button type="button" className="sc-btn" style={{ height: 26 }} disabled={busy || on === all.length} onClick={() => setMany(all.map((s) => s.id), true, t('admin.styles.toast_group_on', { group: name }))}>
                  {t('admin.styles.all_on')}
                </button>
                <button type="button" className="sc-btn" style={{ height: 26 }} disabled={busy || on === 0} onClick={() => setMany(all.map((s) => s.id), false, t('admin.styles.toast_group_off', { group: name }))}>
                  {t('admin.styles.all_off')}
                </button>
              </div>
            </div>
            <div className="sc-list">
              {g.items.map((s) => {
                const isOn = !off.has(s.id);
                return (
                  <div key={s.id} className="sc-row">
                    <div className="w-[220px] flex-shrink-0 transition-opacity" style={{ opacity: isOn ? 1 : 0.4 }}>
                      <TapeStrip style={s} height={16} className="sc-strip" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex min-w-0 items-center gap-2">
                        <span className="truncate text-[13px] font-medium" style={{ color: isOn ? 'var(--text-1)' : 'var(--text-3)' }}>
                          {s.label}
                        </span>
                        {s.region && <Badge>{s.region}</Badge>}
                        {s.custom && <Badge>{t('admin.styles.custom')}</Badge>}
                      </div>
                      <div className="mono mt-1 truncate text-[11.5px]" style={{ color: 'var(--text-4)' }}>
                        {s.id}
                      </div>
                    </div>
                    <Switch
                      on={isOn}
                      label={s.label}
                      disabled={busy || (isOn && onCount <= 1)}
                      onChange={(v) => void act('styles', { ids: [s.id], on: v }, t(v ? 'admin.styles.toast_on' : 'admin.styles.toast_off', { name: s.label }))}
                    />
                  </div>
                );
              })}
            </div>
          </section>
        );
      })}
    </ScrollArea>
  );
}
