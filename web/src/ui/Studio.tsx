// The Tape Studio: make a new tape style from any existing one. What is drawn here is painted by
// the same code the world uses (src/paint/tape.ts), at three sizes, so a style can be judged at
// the distance it will mostly be seen from.
//
// No native colour pickers or <select>s: their pop-ups are separate windows that FiveM's
// off-screen browser does not reliably draw. Everything here is drawn by the page itself.
import { useEffect, useMemo, useState } from 'react';
import { Copy, Pin, PinOff, Plus, Save, Trash2, X } from 'lucide-react';
import { FACES } from '../paint/fonts';
import type { EdgeStyle, Fade, FontKey, PatternType, Separator, Style, TapeText } from '../paint/types';
import { useT } from './locale';
import { post } from './nui';
import { TapeStrip } from './TapeStrip';

const CATEGORIES = ['police', 'federal', 'crime', 'fire', 'ems', 'hazard', 'utility', 'plain', 'international', 'custom'];
const PATTERNS: ('none' | PatternType)[] = ['none', 'diagonal', 'blocks', 'checker', 'chevron', 'band', 'dashes', 'dots', 'zigzag', 'lines'];
// The patterns whose stripes, blocks or dots can be made thicker or thinner (shared/schema.lua fill).
const FILLED: PatternType[] = ['diagonal', 'blocks', 'chevron', 'dashes', 'dots', 'zigzag', 'lines'];
const SEPARATORS: Separator[] = ['none', 'dot', 'star', 'bar', 'slash', 'diamond', 'cross', 'chevron'];
const EDGE_STYLES: EdgeStyle[] = ['solid', 'double', 'dashed', 'checker'];
const FADES: ('none' | Fade)[] = ['none', 'gradient', 'split'];
const PIN_KEY = 'sd_policetape:studioPin';
const PALETTE = [
  '#F6D10E', '#FFE45C', '#F2C14E', '#F26B1D', '#ED2939', '#C8102E', '#9E1B1B', '#B5179E',
  '#0B3D91', '#1565C0', '#002395', '#13216A', '#10263F', '#0A1F44', '#0E8A4A', '#1F4D2B',
  '#C9A86A', '#2B2116', '#ECE6D4', '#FFFFFF', '#E8E8E8', '#BFC5CC', '#5B636B', '#121212',
];
const MAX_LINES = 6;

const DEFAULT_TEXT: TapeText = {
  items: ['DO NOT CROSS'],
  color: '#121212',
  altColor: false,
  font: 'oswald',
  size: 0.6,
  spacing: 0.04,
  width: 1,
  offset: 0,
  italic: false,
  plate: false,
  outline: false,
  shadow: false,
  separator: 'none',
  separatorColor: false,
  separatorSize: 1,
  repeats: 1,
};

function readPin(): boolean {
  try {
    return localStorage.getItem(PIN_KEY) === '1';
  } catch {
    return false;
  }
}

function writePin(on: boolean): void {
  try {
    localStorage.setItem(PIN_KEY, on ? '1' : '0');
  } catch {
    /* (a page without storage just forgets) */
  }
}

/** A fresh copy of a style to edit, as a new custom style. */
function draftFrom(src: Style, label: string): Style {
  const copy: Style = JSON.parse(JSON.stringify(src));
  copy.id = '';
  copy.label = label;
  copy.custom = true;
  return copy;
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[150px_1fr] items-center gap-4 px-4 py-2.5 [&+&]:border-t [&+&]:border-hairline">
      <span className="text-[12.5px] text-t2">{label}</span>
      <div className="flex min-w-0 flex-wrap items-center gap-2.5">{children}</div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h3 className="sc-heading mb-2">{title}</h3>
      <div className="sc-card">{children}</div>
    </section>
  );
}

function Segmented<V extends string | number>({
  value,
  options,
  onChange,
  render,
}: {
  value: V;
  options: V[];
  onChange: (v: V) => void;
  render: (v: V) => React.ReactNode;
}) {
  return (
    <div className="sc-segment">
      {options.map((o) => (
        <button key={String(o)} type="button" data-on={value === o} onClick={() => onChange(o)}>
          {render(o)}
        </button>
      ))}
    </div>
  );
}

function Slider({ value, min, max, step, onChange, suffix }: { value: number; min: number; max: number; step: number; onChange: (v: number) => void; suffix?: string }) {
  return (
    <span className="flex items-center gap-3">
      <input type="range" className="sc-range w-[200px]" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      <span className="mono w-[44px] text-right text-[12px] text-t2">
        {Number.isInteger(step) ? value : value.toFixed(2)}
        {suffix ?? ''}
      </span>
    </span>
  );
}

function Colour({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [hex, setHex] = useState(value);
  useEffect(() => setHex(value), [value]);
  return (
    <span className="flex items-start gap-4">
      <input
        value={hex}
        maxLength={7}
        onChange={(e) => {
          const v = e.target.value.startsWith('#') ? e.target.value : `#${e.target.value}`;
          setHex(v);
          if (/^#[0-9a-fA-F]{6}$/.test(v)) onChange(v.toUpperCase());
        }}
        className="sc-input mono w-[92px] uppercase"
      />
      <span className="grid grid-cols-12 gap-[7px] pt-[6px]">
        {PALETTE.map((c) => (
          <button key={c} type="button" className="sc-swatch" data-on={c === value} style={{ background: c }} onClick={() => onChange(c)} aria-label={c} />
        ))}
      </span>
    </span>
  );
}

function OnOff({ on, onChange }: { on: boolean; onChange: (v: boolean) => void }) {
  const t = useT();
  return <Segmented value={on ? 1 : 0} options={[0, 1]} onChange={(v) => onChange(v === 1)} render={(v) => (v ? t('studio.on') : t('studio.off'))} />;
}

interface Props {
  styles: Style[];
  startFrom: string;
  onClose: () => void;
  result: { ok: boolean; id?: string; error?: string; serial: number } | null;
}

export function Studio({ styles, startFrom, onClose, result }: Props) {
  const t = useT();
  const custom = useMemo(() => styles.filter((s) => s.custom), [styles]);
  const base = styles.find((s) => s.id === startFrom) ?? styles[0];

  const [draft, setDraft] = useState<Style>(() => draftFrom(base, `${base.label} 2`));
  const [dirty, setDirty] = useState(false);
  const [showStart, setShowStart] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [status, setStatus] = useState<'' | 'saving' | 'saved' | 'error'>('');
  const [error, setError] = useState('');
  // The proof stays at the top of the column while everything under it scrolls.
  const [pinned, setPinned] = useState(readPin);

  // The server's answer to a save or delete.
  useEffect(() => {
    if (!result) return;
    if (result.ok) {
      setStatus('saved');
      setDirty(false);
      if (result.id) setDraft((d) => ({ ...d, id: result.id! }));
    } else {
      setStatus('error');
      setError(result.error ?? '');
    }
  }, [result]);

  // A saved style that the server has normalised comes back in `styles`: edit that copy.
  useEffect(() => {
    if (!draft.id || dirty) return;
    const fresh = styles.find((s) => s.id === draft.id);
    if (fresh && JSON.stringify(fresh) !== JSON.stringify(draft)) setDraft(JSON.parse(JSON.stringify(fresh)));
  }, [styles, draft, dirty]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (showStart) setShowStart(false);
        else onClose();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, showStart]);

  function edit(fn: (d: Style) => void) {
    setDraft((d) => {
      const next: Style = JSON.parse(JSON.stringify(d));
      fn(next);
      return next;
    });
    setDirty(true);
    setStatus('');
    setConfirmDelete(false);
  }

  function editText(fn: (tx: TapeText) => void) {
    edit((d) => {
      if (!d.text) d.text = JSON.parse(JSON.stringify(DEFAULT_TEXT));
      fn(d.text as TapeText);
    });
  }

  function open(s: Style) {
    setDraft(JSON.parse(JSON.stringify(s)));
    setDirty(false);
    setStatus('');
    setConfirmDelete(false);
  }

  function startNew(s: Style) {
    setDraft(draftFrom(s, `${s.label} 2`));
    setDirty(true);
    setStatus('');
    setShowStart(false);
  }

  function save(asNew: boolean) {
    setStatus('saving');
    void post('studioSave', { style: { ...draft, id: asNew ? '' : draft.id } });
  }

  function remove() {
    if (!confirmDelete) {
      setConfirmDelete(true);
      return;
    }
    void post('studioDelete', { id: draft.id });
    setConfirmDelete(false);
    startNew(base);
  }

  const tx = draft.text;
  const pattern = draft.pattern;

  return (
    <div className="studio fixed inset-0 flex items-center justify-center animate-fadeIn" style={{ backgroundColor: 'rgba(0,0,0,0.45)' }}>
      <div className="sc-window animate-panelIn" style={{ width: 1180, maxWidth: '94vw', height: '88vh' }}>
        <div className="sc-window__head">
          <div className="flex min-w-0 items-baseline gap-2.5">
            <span className="sc-title">{t('studio.title')}</span>
            <span className="sc-subtitle">{t('studio.subtitle')}</span>
          </div>
          <div className="ml-auto flex items-center gap-3">
            {dirty && <span className="sc-status sc-status--warn">{t('studio.unsaved')}</span>}
            <button type="button" className="sc-btn sc-btn--icon" onClick={onClose} aria-label={t('studio.close')}>
              <X size={16} />
            </button>
          </div>
        </div>

        <div className="grid min-h-0 flex-1 grid-cols-[280px_1fr] gap-5 border-t border-hairline px-5 pt-5">
          {/* Your styles */}
          <nav className="flex min-h-0 flex-col pb-5">
            <h2 className="sc-heading mb-2.5">
              {t('studio.yours')}
              <span className="sc-heading__count">{custom.length}</span>
            </h2>
            <div className="scroll min-h-0 flex-1 overflow-y-auto">
              {custom.length === 0 ? (
                <p className="text-[12.5px] leading-relaxed text-t3">{t('studio.none')}</p>
              ) : (
                <div className="sc-list">
                  {custom.map((s) => (
                    <button key={s.id} type="button" className="sc-row" data-on={s.id === draft.id} onClick={() => open(s)}>
                      <span className="block truncate text-[13px] font-medium text-t1">{s.label}</span>
                      <TapeStrip style={s} height={12} className="sc-strip mt-2" />
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="relative mt-3">
              <button type="button" className="sc-btn w-full" onClick={() => setShowStart((v) => !v)}>
                <Plus size={14} />
                {t('studio.new_style')}
              </button>
              {showStart && (
                <div className="scroll absolute bottom-10 left-0 z-30 max-h-[420px] w-[320px] overflow-y-auto rounded-lg border border-[var(--hairline-strong)] bg-surface2 p-1 shadow-[0_14px_36px_rgba(0,0,0,0.5)] animate-fadeIn">
                  <div className="px-2 pb-1 pt-1.5 text-[11px] font-medium text-t3">{t('studio.start_from')}</div>
                  {styles.map((s) => (
                    <button key={s.id} type="button" onClick={() => startNew(s)} className="block w-full rounded-md px-2 py-1.5 text-left hover:bg-surface3">
                      <span className="block truncate text-[12.5px] text-t1">{s.label}</span>
                      <TapeStrip style={s} height={10} className="sc-strip mt-1.5" />
                    </button>
                  ))}
                </div>
              )}
            </div>
          </nav>

          {/* The style */}
          <div className="scroll flex min-h-0 flex-col gap-5 overflow-y-auto pb-5 pr-1">
            <div className={`sc-card p-4 pt-3 ${pinned ? 'sticky top-0 z-20 shadow-[0_14px_30px_rgba(0,0,0,0.6)]' : ''}`}>
              <div className="mb-2.5 flex items-center gap-2">
                <span className="sc-label">{t('studio.preview')}</span>
                <button
                  type="button"
                  className={`sc-btn ml-auto h-7 px-2.5 text-[12px] ${pinned ? 'sc-btn--on' : ''}`}
                  title={t(pinned ? 'studio.unpin' : 'studio.pin')}
                  onClick={() => {
                    setPinned(!pinned);
                    writePin(!pinned);
                  }}
                >
                  {pinned ? <PinOff size={13} /> : <Pin size={13} />}
                  {t(pinned ? 'studio.unpin' : 'studio.pin')}
                </button>
              </div>
              <TapeStrip style={draft} height={52} className="sc-strip" />
              <div className="mt-4 grid grid-cols-3 gap-4">
                {[
                  [t('studio.close_up'), 20],
                  [t('studio.at_10'), 8],
                  [t('studio.at_30'), 4],
                ].map(([label, h]) => (
                  <div key={String(label)}>
                    <div className="sc-label mb-1.5">{label}</div>
                    <TapeStrip style={draft} height={Number(h)} className="sc-strip" />
                  </div>
                ))}
              </div>
            </div>

            <Section title={t('studio.details')}>
              <Row label={t('studio.name')}>
                <input value={draft.label} maxLength={40} onChange={(e) => edit((d) => (d.label = e.target.value))} className="sc-input w-[300px]" />
              </Row>
              <Row label={t('studio.region')}>
                <input
                  value={draft.region || ''}
                  maxLength={3}
                  placeholder="US"
                  onChange={(e) => edit((d) => (d.region = e.target.value.toUpperCase().replace(/[^A-Z]/g, '') || false))}
                  className="sc-input w-[72px] uppercase"
                />
              </Row>
              <Row label={t('studio.category')}>
                <Segmented value={draft.category} options={CATEGORIES} onChange={(v) => edit((d) => (d.category = v))} render={(v) => t(`categories.${v}`)} />
              </Row>
            </Section>

            <Section title={t('studio.look')}>
              <Row label={t('studio.background')}>
                <Colour value={draft.base} onChange={(v) => edit((d) => (d.base = v))} />
              </Row>
              <Row label={t('studio.second_colour')}>
                <Segmented
                  value={draft.base2 ? draft.base2.mode : 'none'}
                  options={FADES}
                  render={(v) => t(`studio.fades.${v}`)}
                  onChange={(v) => edit((d) => (d.base2 = v === 'none' ? false : { color: d.base2 ? d.base2.color : '#FFFFFF', mode: v }))}
                />
              </Row>
              {draft.base2 && (
                <Row label={t('studio.second_colour')}>
                  <Colour value={draft.base2.color} onChange={(v) => edit((d) => d.base2 && (d.base2.color = v))} />
                </Row>
              )}
              <Row label={t('studio.pattern')}>
                <Segmented
                  value={pattern ? pattern.type : 'none'}
                  options={PATTERNS}
                  render={(v) => t(`studio.patterns.${v}`)}
                  onChange={(v) =>
                    edit((d) => {
                      const p = d.pattern;
                      d.pattern =
                        v === 'none'
                          ? false
                          : { type: v, color: p ? p.color : '#121212', size: p ? p.size : 0.6, angle: p ? p.angle : 45, opacity: p ? p.opacity ?? 1 : 1, fill: p ? p.fill ?? 0.5 : 0.5 };
                    })
                  }
                />
              </Row>
              {pattern && (
                <>
                  <Row label={t('studio.pattern')}>
                    <Colour value={pattern.color} onChange={(v) => edit((d) => d.pattern && (d.pattern.color = v))} />
                  </Row>
                  <Row label={t('studio.pattern_size')}>
                    <Slider value={pattern.size} min={0.15} max={4} step={0.05} onChange={(v) => edit((d) => d.pattern && (d.pattern.size = v))} />
                  </Row>
                  {FILLED.includes(pattern.type) && (
                    <Row label={t('studio.pattern_fill')}>
                      <Slider value={pattern.fill ?? 0.5} min={0.15} max={0.85} step={0.01} onChange={(v) => edit((d) => d.pattern && (d.pattern.fill = v))} />
                    </Row>
                  )}
                  <Row label={t('studio.pattern_opacity')}>
                    <Slider value={pattern.opacity ?? 1} min={0.1} max={1} step={0.01} onChange={(v) => edit((d) => d.pattern && (d.pattern.opacity = v))} />
                  </Row>
                  {pattern.type === 'diagonal' && (
                    <Row label={t('studio.pattern_angle')}>
                      <Slider value={pattern.angle} min={-75} max={75} step={1} suffix="°" onChange={(v) => edit((d) => d.pattern && (d.pattern.angle = v))} />
                    </Row>
                  )}
                </>
              )}
              <Row label={t('studio.edges')}>
                <OnOff on={!!draft.edges} onChange={(on) => edit((d) => (d.edges = on ? { color: '#121212', size: 0.08, style: 'solid', inset: 0 } : false))} />
              </Row>
              {draft.edges && (
                <>
                  <Row label={t('studio.edge_style')}>
                    <Segmented
                      value={draft.edges.style ?? 'solid'}
                      options={EDGE_STYLES}
                      render={(v) => t(`studio.edge_styles.${v}`)}
                      onChange={(v) => edit((d) => d.edges && (d.edges.style = v))}
                    />
                  </Row>
                  <Row label={t('studio.edges')}>
                    <Colour value={draft.edges.color} onChange={(v) => edit((d) => d.edges && (d.edges.color = v))} />
                  </Row>
                  <Row label={t('studio.edge_size')}>
                    <Slider value={draft.edges.size} min={0.02} max={0.3} step={0.01} onChange={(v) => edit((d) => d.edges && (d.edges.size = v))} />
                  </Row>
                  <Row label={t('studio.edge_inset')}>
                    <Slider value={draft.edges.inset ?? 0} min={0} max={0.2} step={0.01} onChange={(v) => edit((d) => d.edges && (d.edges.inset = v))} />
                  </Row>
                </>
              )}
            </Section>

            <Section title={t('studio.text')}>
              <Row label={t('studio.text')}>
                <div className="flex w-full flex-col gap-2">
                  {(tx ? tx.items : []).map((item, i) => (
                    <span key={i} className="flex items-center gap-2">
                      <input
                        value={item}
                        maxLength={32}
                        placeholder={t('studio.line_placeholder')}
                        onChange={(e) => editText((x) => (x.items[i] = e.target.value))}
                        className="sc-input w-[340px]"
                      />
                      <button
                        type="button"
                        className="sc-btn sc-btn--icon sc-btn--danger"
                        aria-label={t('studio.delete')}
                        onClick={() =>
                          edit((d) => {
                            if (!d.text) return;
                            d.text.items.splice(i, 1);
                            if (d.text.items.length === 0) d.text = false;
                          })
                        }
                      >
                        <X size={14} />
                      </button>
                    </span>
                  ))}
                  {(!tx || tx.items.length < MAX_LINES) && (
                    <button type="button" className="sc-btn w-fit" onClick={() => editText((x) => x.items.push(''))}>
                      <Plus size={14} />
                      {t('studio.add_line')}
                    </button>
                  )}
                </div>
              </Row>

              {tx && (
                <>
                  <Row label={t('studio.font')}>
                    <div className="grid grid-cols-4 gap-1.5">
                      {FACES.map((f) => (
                        <button
                          key={f.key}
                          type="button"
                          onClick={() => editText((x) => (x.font = f.key as FontKey))}
                          style={{ fontFamily: `"${f.family}"`, fontWeight: f.weight }}
                          className={`sc-btn h-8 justify-start truncate text-[14px] ${tx.font === f.key ? '!border-[rgba(255,255,255,0.28)] bg-surface3' : ''}`}
                        >
                          {f.name}
                        </button>
                      ))}
                    </div>
                  </Row>
                  <Row label={t('studio.text_color')}>
                    <Colour value={tx.color} onChange={(v) => editText((x) => (x.color = v))} />
                  </Row>
                  <Row label={t('studio.alt_color')}>
                    <OnOff on={!!tx.altColor} onChange={(on) => editText((x) => (x.altColor = on ? '#C8102E' : false))} />
                  </Row>
                  {tx.altColor && (
                    <Row label={t('studio.alt_color')}>
                      <Colour value={tx.altColor} onChange={(v) => editText((x) => (x.altColor = v))} />
                    </Row>
                  )}
                  <Row label={t('studio.italic')}>
                    <OnOff on={tx.italic} onChange={(on) => editText((x) => (x.italic = on))} />
                  </Row>
                  <Row label={t('studio.text_size')}>
                    <Slider value={tx.size} min={0.2} max={0.95} step={0.01} onChange={(v) => editText((x) => (x.size = v))} />
                  </Row>
                  <Row label={t('studio.text_width')}>
                    <Slider value={tx.width ?? 1} min={0.6} max={1.5} step={0.01} onChange={(v) => editText((x) => (x.width = v))} />
                  </Row>
                  <Row label={t('studio.spacing')}>
                    <Slider value={tx.spacing} min={-0.05} max={0.4} step={0.01} onChange={(v) => editText((x) => (x.spacing = v))} />
                  </Row>
                  <Row label={t('studio.text_offset')}>
                    <Slider value={tx.offset ?? 0} min={-0.3} max={0.3} step={0.01} onChange={(v) => editText((x) => (x.offset = v))} />
                  </Row>
                  <Row label={t('studio.repeats')}>
                    <Segmented value={tx.repeats} options={[1, 2, 3, 4]} onChange={(v) => editText((x) => (x.repeats = v))} render={(v) => String(v)} />
                  </Row>
                  <Row label={t('studio.separator')}>
                    <Segmented value={tx.separator} options={SEPARATORS} onChange={(v) => editText((x) => (x.separator = v))} render={(v) => t(`studio.separators.${v}`)} />
                  </Row>
                  {tx.separator !== 'none' && (
                    <>
                      <Row label={t('studio.separator_color')}>
                        <Colour value={tx.separatorColor || tx.color} onChange={(v) => editText((x) => (x.separatorColor = v))} />
                      </Row>
                      <Row label={t('studio.separator_size')}>
                        <Slider value={tx.separatorSize ?? 1} min={0.5} max={2} step={0.05} onChange={(v) => editText((x) => (x.separatorSize = v))} />
                      </Row>
                    </>
                  )}
                  <Row label={t('studio.plate')}>
                    <OnOff on={!!tx.plate} onChange={(on) => editText((x) => (x.plate = on ? { color: draft.base, padding: 0.25, radius: 0 } : false))} />
                  </Row>
                  {tx.plate && (
                    <>
                      <Row label={t('studio.plate')}>
                        <Colour value={tx.plate.color} onChange={(v) => editText((x) => x.plate && (x.plate.color = v))} />
                      </Row>
                      <Row label={t('studio.plate_padding')}>
                        <Slider value={tx.plate.padding} min={0} max={1} step={0.01} onChange={(v) => editText((x) => x.plate && (x.plate.padding = v))} />
                      </Row>
                      <Row label={t('studio.plate_radius')}>
                        <Slider value={tx.plate.radius ?? 0} min={0} max={0.5} step={0.01} onChange={(v) => editText((x) => x.plate && (x.plate.radius = v))} />
                      </Row>
                    </>
                  )}
                  <Row label={t('studio.shadow')}>
                    <OnOff on={!!tx.shadow} onChange={(on) => editText((x) => (x.shadow = on ? { color: '#000000', distance: 0.04 } : false))} />
                  </Row>
                  {tx.shadow && (
                    <>
                      <Row label={t('studio.shadow')}>
                        <Colour value={tx.shadow.color} onChange={(v) => editText((x) => x.shadow && (x.shadow.color = v))} />
                      </Row>
                      <Row label={t('studio.shadow_distance')}>
                        <Slider value={tx.shadow.distance} min={0.01} max={0.15} step={0.01} onChange={(v) => editText((x) => x.shadow && (x.shadow.distance = v))} />
                      </Row>
                    </>
                  )}
                  <Row label={t('studio.outline')}>
                    <OnOff on={!!tx.outline} onChange={(on) => editText((x) => (x.outline = on ? { color: '#FFFFFF', width: 0.08 } : false))} />
                  </Row>
                  {tx.outline && (
                    <>
                      <Row label={t('studio.outline')}>
                        <Colour value={tx.outline.color} onChange={(v) => editText((x) => x.outline && (x.outline.color = v))} />
                      </Row>
                      <Row label={t('studio.outline_width')}>
                        <Slider value={tx.outline.width} min={0.01} max={0.3} step={0.01} onChange={(v) => editText((x) => x.outline && (x.outline.width = v))} />
                      </Row>
                    </>
                  )}
                </>
              )}
            </Section>
          </div>
        </div>

        <div className="flex h-14 shrink-0 items-center gap-2 border-t border-hairline px-5">
          <span className="min-w-0 flex-1 truncate">
            {status === 'saving' && <span className="sc-status">{t('studio.saving')}</span>}
            {status === 'saved' && <span className="sc-status sc-status--ok">{t('studio.saved')}</span>}
            {status === 'error' && <span className="sc-status sc-status--danger">{error}</span>}
          </span>
          {draft.id && (
            <button type="button" onClick={remove} className={`sc-btn ${confirmDelete ? 'sc-btn--danger-solid' : 'sc-btn--danger'}`}>
              <Trash2 size={14} />
              {confirmDelete ? t('studio.confirm_delete') : t('studio.delete')}
            </button>
          )}
          {draft.id && (
            <button type="button" className="sc-btn" onClick={() => save(true)}>
              <Copy size={14} />
              {t('studio.save_new')}
            </button>
          )}
          <button type="button" className="sc-btn sc-btn--primary" onClick={() => save(false)} disabled={status === 'saving'}>
            <Save size={14} />
            {t('studio.save')}
          </button>
        </div>
      </div>
    </div>
  );
}
