// The admin menu's parts, as sd-computers has them (web/src/admin/components/shared.tsx): badge,
// status, heading, empty state, hint, modal and confirm dialog, toasts, search, switch, and the
// two hooks that make them close in the right order and leave with an animation.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { ReactNode, RefObject } from 'react';
import { Search, X } from 'lucide-react';
import { useT } from '../locale';
import { useAdmin } from './store';

const escapeStack: { current: () => void }[] = [];
let escapeBound = false;

function bindEscape() {
  if (escapeBound) return;
  escapeBound = true;
  window.addEventListener(
    'keydown',
    (e) => {
      if (e.key !== 'Escape' || escapeStack.length === 0) return;
      e.stopPropagation();
      e.preventDefault();
      escapeStack[escapeStack.length - 1].current();
    },
    true,
  );
}

/** Escape closes the newest thing that asked for it: a dialog before the panel under it. */
export function useEscape(onClose: () => void): void {
  const entry = useRef({ current: onClose });
  entry.current.current = onClose;
  useEffect(() => {
    bindEscape();
    const item = entry.current;
    escapeStack.push(item);
    return () => {
      const i = escapeStack.lastIndexOf(item);
      if (i >= 0) escapeStack.splice(i, 1);
    };
  }, []);
}

// Leaving, animated: React takes an element away at once, so its last frame is copied and the copy
// is left where it was to play `exitClass`, then removed. `float` lifts the copy out of the flow.
export function useExitGhost(ref: RefObject<HTMLElement | null>, exitClass: string, ms = 180, float = false): void {
  useLayoutEffect(() => {
    const el = ref.current;
    return () => {
      if (!el || !el.parentNode) return;
      const parent = el.parentNode;
      const next = el.nextSibling;
      const ghost = el.cloneNode(true) as HTMLElement;
      if (float) Object.assign(ghost.style, { position: 'absolute', left: `${el.offsetLeft}px`, top: `${el.offsetTop}px`, width: `${el.offsetWidth}px`, margin: '0' });
      queueMicrotask(() => {
        if (el.isConnected || !(parent as Node).isConnected) return;
        ghost.removeAttribute('data-modal');
        ghost.setAttribute('aria-hidden', 'true');
        ghost.style.pointerEvents = 'none';
        ghost.classList.add(exitClass);
        parent.insertBefore(ghost, next && next.parentNode === parent ? next : null);
        window.setTimeout(() => ghost.remove(), ms);
      });
    };
  }, [ref, exitClass, ms, float]);
}

type Tone = 'neutral' | 'accent' | 'danger' | 'warn';

export const Badge = ({ children, tone = 'neutral', title }: { children: ReactNode; tone?: Tone; title?: string }) => {
  const styles: Record<Tone, { bg: string; fg: string }> = {
    neutral: { bg: 'rgba(255,255,255,0.06)', fg: 'var(--text-2)' },
    accent: { bg: 'var(--ok-soft)', fg: 'var(--ok)' },
    danger: { bg: 'var(--danger-soft)', fg: 'var(--danger)' },
    warn: { bg: 'var(--warn-soft)', fg: 'var(--warn)' },
  };
  const s = styles[tone];
  return (
    <span title={title} className="mono inline-flex h-[18px] items-center whitespace-nowrap rounded px-1.5 text-[11px] font-medium" style={{ backgroundColor: s.bg, color: s.fg }}>
      {children}
    </span>
  );
};

export const Heading = ({ title, count, children }: { title: string; count?: number; children?: ReactNode }) => (
  <div className="flex min-h-[30px] items-center gap-3">
    <div className="sc-heading">
      {title}
      {count != null && <span className="sc-heading__count">{count}</span>}
    </div>
    {children && <div className="ml-auto flex items-center gap-2">{children}</div>}
  </div>
);

export const Empty = ({ text }: { text: string }) => (
  <div className="flex h-full min-h-[140px] items-center justify-center text-[12.5px]" style={{ color: 'var(--text-3)' }}>
    {text}
  </div>
);

export const Hint = ({ children, className = '' }: { children: ReactNode; className?: string }) => (
  <p className={`m-0 text-[11.5px] leading-relaxed ${className}`} style={{ color: 'var(--text-3)' }}>
    {children}
  </p>
);

export const Switch = ({ on, label, disabled, onChange }: { on: boolean; label: string; disabled?: boolean; onChange(on: boolean): void }) => (
  <button type="button" role="switch" aria-checked={on} aria-label={label} title={label} className="sc-switch" data-on={on} disabled={disabled} onClick={() => onChange(!on)} />
);

export const Modal = ({ title, onClose, children, width = 420 }: { title: ReactNode; onClose: () => void; children: ReactNode; width?: number }) => {
  const t = useT();
  useEscape(onClose);
  const root = useRef<HTMLDivElement>(null);
  useExitGhost(root, 'animate-modalOut', 160);
  return (
    <div
      ref={root}
      data-modal
      className="fixed inset-0 z-40 flex animate-fadeIn items-center justify-center"
      style={{ backgroundColor: 'rgba(0,0,0,0.5)' }}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="relative animate-modalIn overflow-hidden rounded-[12px]"
        style={{ width, maxWidth: '92%', backgroundColor: 'var(--surface)', border: '1px solid var(--hairline-strong)', boxShadow: '0 20px 50px rgba(0,0,0,0.5)' }}
      >
        <div className="flex h-12 items-center gap-3 pl-5 pr-3">
          <span className="text-[14px] font-semibold">{title}</span>
          <button type="button" className="sc-btn sc-btn--icon ml-auto" onClick={onClose} aria-label={t('admin.common.close')}>
            <X size={15} />
          </button>
        </div>
        <div className="px-5 pb-5 pt-1">{children}</div>
      </div>
    </div>
  );
};

export const ConfirmDialog = ({
  title,
  body,
  confirmLabel,
  onConfirm,
  onClose,
  danger = true,
}: {
  title: string;
  body: string;
  confirmLabel?: string;
  onConfirm: () => void | Promise<void>;
  onClose: () => void;
  danger?: boolean;
}) => {
  const t = useT();
  const [working, setWorking] = useState(false);
  return (
    <Modal title={title} onClose={onClose} width={380}>
      <p className="m-0 text-[13px] leading-relaxed" style={{ color: 'var(--text-2)' }}>
        {body}
      </p>
      <div className="mt-5 flex justify-end gap-2">
        <button type="button" className="sc-btn" onClick={onClose} disabled={working}>
          {t('admin.common.cancel')}
        </button>
        <button
          type="button"
          className={`sc-btn ${danger ? 'sc-btn--danger-solid' : 'sc-btn--primary'}`}
          disabled={working}
          onClick={async () => {
            setWorking(true);
            await onConfirm();
            setWorking(false);
          }}
        >
          {confirmLabel ?? t('admin.common.confirm')}
        </button>
      </div>
    </Modal>
  );
};

export const Toasts = () => {
  const toasts = useAdmin((s) => s.toasts);
  return (
    <div className="pointer-events-none absolute bottom-5 left-1/2 z-50 flex -translate-x-1/2 flex-col items-center gap-2">
      {toasts.map((tt) => (
        <ToastItem key={tt.id} text={tt.text} ok={tt.ok} />
      ))}
    </div>
  );
};

const ToastItem = ({ text, ok }: { text: string; ok: boolean }) => {
  const root = useRef<HTMLDivElement>(null);
  useExitGhost(root, 'animate-toastOut', 170, true);
  return (
    <div
      ref={root}
      className="flex h-9 animate-toastIn items-center gap-2.5 rounded-lg pl-3 pr-3.5 text-[12.5px] font-medium"
      style={{ backgroundColor: 'var(--surface-3)', border: '1px solid var(--hairline-strong)', color: 'var(--text-1)', boxShadow: '0 8px 24px rgba(0,0,0,0.4)' }}
    >
      <span className="h-1.5 w-1.5 flex-shrink-0 rounded-full" style={{ backgroundColor: ok ? 'var(--ok)' : 'var(--danger)' }} />
      {text}
    </div>
  );
};

export const SearchInput = ({ value, onChange, placeholder, hotkey = true }: { value: string; onChange: (v: string) => void; placeholder: string; hotkey?: boolean }) => {
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (!hotkey) return;
    const onKey = (e: KeyboardEvent) => {
      const tag = (document.activeElement as HTMLElement | null)?.tagName;
      if (e.key === '/' && tag !== 'INPUT' && tag !== 'TEXTAREA') {
        e.preventDefault();
        ref.current?.focus();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [hotkey]);
  return (
    <div className="relative min-w-[160px] flex-1">
      <Search size={14} className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2" style={{ color: 'var(--text-3)' }} />
      <input
        ref={ref}
        className="sc-input"
        style={{ paddingLeft: 30, paddingRight: 28 }}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            e.stopPropagation();
            if (value) onChange('');
            else (e.target as HTMLInputElement).blur();
          }
        }}
      />
      {hotkey && !value && <span className="sc-kbd pointer-events-none absolute right-2 top-1/2 -translate-y-1/2">/</span>}
    </div>
  );
};

/** "just now", "5m ago": how long before `now` (the server's clock) `at` was. */
export function ago(t: ReturnType<typeof useT>, at: number | null | undefined, now: number): string {
  if (!at) return '';
  const s = Math.max(0, Math.floor(now - at));
  if (s < 45) return t('admin.common.just_now');
  if (s < 3600) return t('admin.common.ago', { time: `${Math.max(1, Math.round(s / 60))}m` });
  if (s < 86400) return t('admin.common.ago', { time: `${Math.floor(s / 3600)}h` });
  return t('admin.common.ago', { time: `${Math.floor(s / 86400)}d` });
}
