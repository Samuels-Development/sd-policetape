// The admin menu (/tapeadmin). The shell is sd-computers' admin panel (and sd-bombs' before it),
// part for part: the same frame, header, numbered tabs with their counts and sliding underline,
// tabs that come in from the side they sit on, toasts, and a fresh snapshot every 5 s while open.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Loader2, X } from 'lucide-react';
import type { Style } from '../../paint/types';
import { useT } from '../locale';
import { close, refresh } from './api';
import { HoldersTab } from './HoldersTab';
import { SettingsTab } from './SettingsTab';
import { Toasts, useEscape, useExitGhost } from './shared';
import { setTab, setWords, useAdmin } from './store';
import { StylesTab } from './StylesTab';
import { TapesTab } from './TapesTab';
import { TABS, type Tab } from './types';

const REFRESH_MS = 5000;

const typing = () => {
  const el = document.activeElement as HTMLElement | null;
  return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable);
};

export function AdminPanel({ styles }: { styles: Style[] }) {
  const t = useT();
  setWords(t);
  const snapshot = useAdmin((s) => s.snapshot);
  const tab = useAdmin((s) => s.tab);
  const busy = useAdmin((s) => s.busy);

  useEscape(close);
  const root = useRef<HTMLDivElement>(null);
  useExitGhost(root, 'animate-panelOut', 180);

  // Which way the tabs moved: the new one comes in from the side it sits on.
  const enter = useRef<{ tab: Tab; cls: string }>({ tab, cls: '' });
  if (enter.current.tab !== tab) {
    enter.current = { tab, cls: TABS.indexOf(tab) > TABS.indexOf(enter.current.tab) ? 'animate-tabFromRight' : 'animate-tabFromLeft' };
  }

  const tabRefs = useRef<Partial<Record<Tab, HTMLButtonElement | null>>>({});
  const [underline, setUnderline] = useState<{ left: number; width: number } | null>(null);
  useLayoutEffect(() => {
    const el = tabRefs.current[tab];
    if (!el) return;
    setUnderline({ left: el.offsetLeft + 10, width: Math.max(0, el.offsetWidth - 20) });
  }, [tab, snapshot]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.altKey || e.metaKey || typing()) return;
      const n = Number(e.key);
      if (Number.isInteger(n) && n >= 1 && n <= TABS.length && !document.querySelector('[data-modal]')) setTab(TABS[n - 1]);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    const id = window.setInterval(() => {
      if (!document.querySelector('[data-modal]')) void refresh();
    }, REFRESH_MS);
    return () => window.clearInterval(id);
  }, []);

  if (!snapshot) return null;

  const offStyles = new Set(snapshot.offStyles);
  const offHolders = new Set(snapshot.offHolders);
  const counts: Partial<Record<Tab, number>> = {
    tapes: snapshot.tapes.length,
    styles: styles.filter((s) => !offStyles.has(s.id)).length,
    holders: snapshot.holders.filter((h) => !offHolders.has(h.id)).length,
  };

  return (
    <div ref={root} className="sc-admin fixed inset-0 flex animate-fadeIn items-center justify-center font-sans" style={{ backgroundColor: 'rgba(0,0,0,0.45)' }}>
      <div
        className="relative flex animate-panelIn flex-col overflow-hidden"
        style={{
          width: 1180,
          maxWidth: '94vw',
          height: '88vh',
          borderRadius: 14,
          backgroundColor: 'var(--bg)',
          border: '1px solid var(--hairline-strong)',
          boxShadow: '0 30px 80px rgba(0,0,0,0.55)',
        }}
      >
        <div className="flex h-14 flex-shrink-0 items-center gap-3 pl-5 pr-3">
          <div className="flex min-w-0 items-baseline gap-2.5">
            <span className="text-[14.5px] font-semibold tracking-[-0.01em]">{t('admin.title')}</span>
            <span className="truncate text-[12.5px]" style={{ color: 'var(--text-3)' }}>
              {t('admin.subtitle')}
            </span>
          </div>
          <div className="ml-auto flex items-center gap-2">
            {busy && <Loader2 size={14} className="animate-spin" style={{ color: 'var(--text-3)' }} />}
            <button type="button" className="sc-btn sc-btn--icon" onClick={close} aria-label={t('admin.common.close')}>
              <X size={16} />
            </button>
          </div>
        </div>

        <div className="relative flex flex-shrink-0 items-center px-3" style={{ borderBottom: '1px solid var(--hairline)' }}>
          {TABS.map((id, i) => (
            <button
              key={id}
              type="button"
              ref={(el) => {
                tabRefs.current[id] = el;
              }}
              data-on={tab === id}
              title={`${i + 1}`}
              onClick={() => setTab(id)}
              className="sc-tab"
            >
              {t(`admin.tabs.${id}`)}
              {counts[id] != null && <span className="sc-tab__count">{counts[id]}</span>}
            </button>
          ))}
          {underline && <span className="sc-tab-underline absolute -bottom-px h-[1.5px] rounded-full" style={{ left: underline.left, width: underline.width, backgroundColor: 'var(--text-1)' }} />}
        </div>

        <div className="relative min-h-0 flex-1 overflow-hidden">
          <div key={tab} className={`absolute inset-0 ${enter.current.cls}`}>
            {tab === 'tapes' && <TapesTab styles={styles} />}
            {tab === 'styles' && <StylesTab styles={styles} />}
            {tab === 'holders' && <HoldersTab />}
            {tab === 'settings' && <SettingsTab />}
          </div>
        </div>

        <Toasts />
      </div>
    </div>
  );
}
