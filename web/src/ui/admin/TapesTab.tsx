// Every tape on the server: what it is, who put it up, where, and when, with a waypoint to it, a
// way to go there, and taking it down - one, every torn one, or all of them.
import { useMemo, useState } from 'react';
import { MapPin, Navigation, Scissors, Trash2 } from 'lucide-react';
import type { Style } from '../../paint/types';
import { useT } from '../locale';
import { TapeStrip } from '../TapeStrip';
import { act, teleport, waypoint } from './api';
import { ScrollArea } from './ScrollArea';
import { Badge, ConfirmDialog, Empty, Heading, SearchInput, ago } from './shared';
import { toast, useAdmin } from './store';
import type { TapeRow } from './types';

type Filter = 'all' | 'up' | 'torn';

export function TapesTab({ styles }: { styles: Style[] }) {
  const t = useT();
  const snapshot = useAdmin((s) => s.snapshot)!;
  const busy = useAdmin((s) => s.busy);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [confirm, setConfirm] = useState<'all' | 'torn' | null>(null);

  const byId = useMemo(() => new Map(styles.map((s) => [s.id, s])), [styles]);
  const tapes = snapshot.tapes;
  const torn = tapes.filter((r) => r.torn).length;

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase().replace(/^#/, '');
    return tapes.filter((r) => {
      if (filter === 'up' && r.torn) return false;
      if (filter === 'torn' && !r.torn) return false;
      if (!q) return true;
      return `${r.id} ${r.label} ${r.owner ?? ''} ${r.street ?? ''}`.toLowerCase().includes(q);
    });
  }, [tapes, query, filter]);

  const filters: { id: Filter; label: string; count: number }[] = [
    { id: 'all', label: t('admin.tapes.filter_all'), count: tapes.length },
    { id: 'up', label: t('admin.tapes.filter_up'), count: tapes.length - torn },
    { id: 'torn', label: t('admin.tapes.filter_torn'), count: torn },
  ];

  return (
    <ScrollArea className="h-full" viewClassName="flex flex-col gap-4 px-6 py-5">
      <Heading title={t('admin.tapes.title')} count={tapes.length}>
        <span className="mono mr-1 text-[11.5px]" style={{ color: 'var(--text-3)' }}>
          {t('admin.tapes.of_total', { count: tapes.length, total: snapshot.total })}
        </span>
        <button type="button" className="sc-btn" disabled={busy || torn === 0} onClick={() => setConfirm('torn')}>
          <Scissors size={14} />
          {t('admin.tapes.remove_torn')}
        </button>
        <button type="button" className="sc-btn sc-btn--danger" disabled={busy || tapes.length === 0} onClick={() => setConfirm('all')}>
          <Trash2 size={14} />
          {t('admin.tapes.remove_all')}
        </button>
      </Heading>

      <div className="flex flex-shrink-0 items-center gap-2">
        <SearchInput value={query} onChange={setQuery} placeholder={t('admin.tapes.search')} />
        <div className="sc-segment">
          {filters.map((f) => (
            <button key={f.id} type="button" data-on={filter === f.id} onClick={() => setFilter(f.id)}>
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {tapes.length === 0 ? (
        <Empty text={t('admin.tapes.empty')} />
      ) : shown.length === 0 ? (
        <Empty text={t('admin.tapes.no_match')} />
      ) : (
        <div className="sc-list flex-shrink-0">
          {shown.map((r) => (
            <Row key={r.id} r={r} style={byId.get(r.style) ?? styles[0]} now={snapshot.now} busy={busy} />
          ))}
        </div>
      )}

      {confirm && (
        <ConfirmDialog
          title={t(confirm === 'all' ? 'admin.tapes.confirm_all_title' : 'admin.tapes.confirm_torn_title')}
          body={t(confirm === 'all' ? 'admin.tapes.confirm_all_body' : 'admin.tapes.confirm_torn_body', { count: confirm === 'all' ? tapes.length : torn })}
          confirmLabel={t('admin.tapes.confirm_go')}
          onClose={() => setConfirm(null)}
          onConfirm={async () => {
            await act(confirm === 'all' ? 'removeAll' : 'removeTorn', {});
            setConfirm(null);
          }}
        />
      )}
    </ScrollArea>
  );
}

function Row({ r, style, now, busy }: { r: TapeRow; style: Style | undefined; now: number; busy: boolean }) {
  const t = useT();
  const line = [`#${r.id}`, r.owner || t('admin.tapes.by_script'), t('admin.tapes.length', { length: r.length.toFixed(1) }), r.street, ago(t, r.created, now)].filter(Boolean);
  return (
    <div className="sc-row">
      <div className="w-[84px] flex-shrink-0">{style && <TapeStrip style={style} height={16} className="sc-strip" tornRight={r.torn} />}</div>
      <div className="min-w-0 flex-1">
        <div className="flex min-w-0 items-center gap-2.5">
          <span className="truncate text-[13px] font-medium">{r.label}</span>
          {r.torn && <Badge tone="danger">{t('admin.tapes.torn')}</Badge>}
          {r.down && <Badge tone="warn">{t('admin.tapes.down')}</Badge>}
        </div>
        <div className="mono mt-1 truncate text-[11.5px]" style={{ color: 'var(--text-3)' }}>
          {line.join(' · ')}
        </div>
      </div>
      {r.distance != null && (
        <span className="mono flex-shrink-0 text-[11.5px]" style={{ color: 'var(--text-3)' }}>
          {t('admin.tapes.away', { distance: r.distance })}
        </span>
      )}
      <div className="sc-row__actions">
        <button
          type="button"
          className="sc-btn sc-btn--icon"
          title={t('admin.tapes.waypoint')}
          aria-label={t('admin.tapes.waypoint')}
          onClick={() => {
            waypoint(r.id);
            toast(t('admin.tapes.toast_waypoint', { id: r.id }));
          }}
        >
          <MapPin size={14} />
        </button>
        <button type="button" className="sc-btn sc-btn--icon" title={t('admin.tapes.teleport')} aria-label={t('admin.tapes.teleport')} onClick={() => teleport(r.id)}>
          <Navigation size={14} />
        </button>
        <button
          type="button"
          className="sc-btn sc-btn--icon sc-btn--danger"
          title={t('admin.tapes.remove')}
          aria-label={t('admin.tapes.remove')}
          disabled={busy}
          onClick={() => void act('remove', { id: r.id }, t('admin.tapes.toast_removed', { id: r.id }))}
        >
          <Trash2 size={14} />
        </button>
      </div>
    </div>
  );
}
