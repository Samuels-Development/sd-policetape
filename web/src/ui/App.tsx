// The ui_page, all driven by client/nui.lua:
//   the HUD prompt (no focus)       while placing tape or editing a tape
//   the style picker (focus)        choose or change a tape's style
//   the holder menu (focus)         the post or cone a new end stands on
//   the Tape Studio (focus)         make new styles, for players allowed to
//   the admin menu (focus)          every tape on the server, and what police get to put up
import { useEffect, useMemo, useState } from 'react';
import type { Style } from '../paint/types';
import { AdminPanel } from './admin/AdminPanel';
import { setSnapshot } from './admin/store';
import type { Snapshot } from './admin/types';
import { Holders, type HolderCard } from './Holders';
import { Hud, type HudState } from './Hud';
import { LocaleContext, fallback, makeT, type Dict } from './locale';
import { post, useNuiMessages } from './nui';
import { Picker, type Me } from './Picker';
import { Studio } from './Studio';

type StudioResult = { ok: boolean; id?: string; error?: string; serial: number };

const ids = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

export function App() {
  const [dict, setDict] = useState<Dict>(fallback);
  const [styles, setStyles] = useState<Style[]>([]);
  const [off, setOff] = useState<string[]>([]);
  const [me, setMe] = useState<Me | null>(null);
  const [canStudio, setCanStudio] = useState(false);
  const [hud, setHud] = useState<HudState | null>(null);
  const [progress, setProgress] = useState(0);
  const [picker, setPicker] = useState<{ selected: string } | null>(null);
  const [holders, setHolders] = useState<{ list: HolderCard[]; selected: string } | null>(null);
  const [studio, setStudio] = useState<{ startFrom: string } | null>(null);
  const [admin, setAdmin] = useState(false);
  const [result, setResult] = useState<StudioResult | null>(null);
  const [liveId, setLiveId] = useState('');

  useNuiMessages((msg) => {
    switch (msg.action) {
      case 'init':
        if (msg.locale && typeof msg.locale === 'object') setDict(msg.locale as Dict);
        if (Array.isArray(msg.styles)) setStyles(msg.styles as Style[]);
        setOff(ids(msg.off));
        if (msg.me && typeof msg.me === 'object') setMe(msg.me as Me);
        setCanStudio(msg.canStudio === true);
        break;
      case 'me':
        setMe(msg.me && typeof msg.me === 'object' ? (msg.me as Me) : null);
        break;
      case 'styles':
        if (Array.isArray(msg.styles)) setStyles(msg.styles as Style[]);
        if (typeof msg.canStudio === 'boolean') setCanStudio(msg.canStudio);
        break;
      case 'off':
        setOff(ids(msg.styles));
        break;
      case 'hud':
        setHud((msg.hud as HudState) ?? null);
        if (!msg.hud) setProgress(0);
        break;
      case 'progress':
        setProgress(Number(msg.value) || 0);
        break;
      case 'picker':
        if (msg.open) {
          setPicker({ selected: String(msg.selected ?? '') });
          setLiveId(String(msg.selected ?? ''));
        } else setPicker(null);
        break;
      case 'holders':
        if (msg.open && Array.isArray(msg.list)) setHolders({ list: msg.list as HolderCard[], selected: String(msg.selected ?? '') });
        else setHolders(null);
        break;
      case 'studio':
        if (msg.open) setStudio({ startFrom: String(msg.startFrom ?? liveId) });
        else setStudio(null);
        break;
      case 'studioResult':
        setResult({ ok: msg.ok === true, id: msg.id as string | undefined, error: msg.error as string | undefined, serial: Date.now() });
        break;
      case 'admin':
        if (msg.open) setSnapshot(msg.snapshot as Snapshot);
        setAdmin(msg.open === true);
        break;
      case 'adminSnapshot':
        setSnapshot(msg.snapshot as Snapshot);
        break;
    }
  });

  useEffect(() => {
    void post('uiReady');
  }, []);

  const t = useMemo(() => makeT(dict), [dict]);
  const byId = useMemo(() => new Map(styles.map((s) => [s.id, s])), [styles]);
  // What players may put up: the picker offers only these (tape already up keeps its own).
  const offered = useMemo(() => {
    const gone = new Set(off);
    const list = styles.filter((s) => !gone.has(s.id));
    return list.length ? list : styles;
  }, [styles, off]);

  const hudStyle = hud ? byId.get(hud.styleId) ?? styles[0] : undefined;

  function closePicker() {
    setPicker(null);
    void post('pickerClose');
  }

  function closeHolders() {
    setHolders(null);
    void post('holdersClose');
  }

  function closeStudio() {
    setStudio(null);
    void post('studioClose');
  }

  if (styles.length === 0) return null;

  const menu = picker || holders || studio || admin;

  return (
    <LocaleContext.Provider value={t}>
      <div>
        {hud && hudStyle && !menu && <Hud hud={hud} style={hudStyle} progress={progress} />}
        {picker && !studio && (
          <Picker
            styles={offered}
            selected={picker.selected}
            canStudio={canStudio}
            me={me}
            onHover={(id) => {
              setLiveId(id);
              void post('pickerHover', { id });
            }}
            onClose={closePicker}
            onOpenStudio={() => void post('studioOpen', { from: liveId })}
          />
        )}
        {holders && <Holders list={holders.list} selected={holders.selected} onClose={closeHolders} />}
        {studio && <Studio styles={styles} startFrom={studio.startFrom} onClose={closeStudio} result={result} />}
        {admin && <AdminPanel styles={styles} />}
      </div>
    </LocaleContext.Provider>
  );
}
