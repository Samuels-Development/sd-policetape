// The ui_page. Three things, all driven by client/nui.lua:
//   the HUD prompt (no focus)       while placing tape or looking at a tape
//   the style picker (focus)        choose or change a tape's style
//   the Tape Studio (focus)         make new styles, for players allowed to
import { useEffect, useMemo, useState } from 'react';
import type { Style } from '../paint/types';
import { Hud, type HudState } from './Hud';
import { LocaleContext, fallback, makeT, type Dict } from './locale';
import { post, useNuiMessages } from './nui';
import { Picker } from './Picker';
import { Studio } from './Studio';

type StudioResult = { ok: boolean; id?: string; error?: string; serial: number };

export function App() {
  const [dict, setDict] = useState<Dict>(fallback);
  const [styles, setStyles] = useState<Style[]>([]);
  const [canStudio, setCanStudio] = useState(false);
  const [hud, setHud] = useState<HudState | null>(null);
  const [progress, setProgress] = useState(0);
  const [picker, setPicker] = useState<{ selected: string } | null>(null);
  const [studio, setStudio] = useState<{ startFrom: string } | null>(null);
  const [result, setResult] = useState<StudioResult | null>(null);
  const [liveId, setLiveId] = useState('');

  useNuiMessages((msg) => {
    switch (msg.action) {
      case 'init':
        if (msg.locale && typeof msg.locale === 'object') setDict(msg.locale as Dict);
        if (Array.isArray(msg.styles)) setStyles(msg.styles as Style[]);
        setCanStudio(msg.canStudio === true);
        break;
      case 'styles':
        if (Array.isArray(msg.styles)) setStyles(msg.styles as Style[]);
        if (typeof msg.canStudio === 'boolean') setCanStudio(msg.canStudio);
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
      case 'studio':
        if (msg.open) setStudio({ startFrom: String(msg.startFrom ?? liveId) });
        else setStudio(null);
        break;
      case 'studioResult':
        setResult({ ok: msg.ok === true, id: msg.id as string | undefined, error: msg.error as string | undefined, serial: Date.now() });
        break;
    }
  });

  useEffect(() => {
    void post('uiReady');
  }, []);

  const t = useMemo(() => makeT(dict), [dict]);
  const byId = useMemo(() => new Map(styles.map((s) => [s.id, s])), [styles]);

  const hudStyle = hud ? byId.get(hud.styleId) ?? styles[0] : undefined;

  function closePicker() {
    setPicker(null);
    void post('pickerClose');
  }

  function closeStudio() {
    setStudio(null);
    void post('studioClose');
  }

  if (styles.length === 0) return null;

  return (
    <LocaleContext.Provider value={t}>
      <div>
        {hud && hudStyle && !picker && !studio && <Hud hud={hud} style={hudStyle} progress={progress} />}
        {picker && !studio && (
          <Picker
            styles={styles}
            selected={picker.selected}
            canStudio={canStudio}
            onHover={(id) => {
              setLiveId(id);
              void post('pickerHover', { id });
            }}
            onClose={closePicker}
            onOpenStudio={() => void post('studioOpen', { from: liveId })}
          />
        )}
        {studio && <Studio styles={styles} startFrom={studio.startFrom} onClose={closeStudio} result={result} />}
      </div>
    </LocaleContext.Provider>
  );
}
