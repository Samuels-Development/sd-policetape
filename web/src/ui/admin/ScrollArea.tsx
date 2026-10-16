import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { CSSProperties, ReactNode, Ref } from 'react';

// Our scrollbar. The scrolling is the browser's own - wheel, touchpad, keys, focus - only its bar is ours: a slim
// thumb that floats over the content instead of taking a gutter, comes up while the pointer is over the area or it
// is scrolling, widens when reached for, and can be dragged or clicked beside to page. The edges fade where there
// is more to see that way. While there is something to scroll it says so (data-overflow): rows and menus inside it make
// room at their right edge (--sa-gutter, styles.css), so the bar never lies over what is there.
//
// Lay it out like the element it replaces: the outer box takes the size (flex-1 min-h-0, a height, a max-height);
// the view inside fills it and scrolls. `viewClassName` / `viewStyle` style that view (padding, gaps, a flex column).

const IDLE_MS = 900; // how long the thumb stays up after the last scroll
const MIN_THUMB = 28;

export interface ScrollAreaProps {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
  viewClassName?: string;
  viewStyle?: CSSProperties;
  viewRef?: Ref<HTMLDivElement>; // the scrolling element, for a parent that measures or scrolls it
  rootRef?: Ref<HTMLDivElement>; // the whole area, bar included (what a click 'inside' it means)
  rootAttrs?: Record<string, string | boolean | undefined>; // more attributes on the whole area (data-*)
  fade?: boolean; // fade the edges where there is more (default on)
  role?: string;
}

export function ScrollArea({ children, className = '', style, viewClassName = '', viewStyle, viewRef, rootRef, rootAttrs, fade = true, role }: ScrollAreaProps) {
  const view = useRef<HTMLDivElement | null>(null);
  const track = useRef<HTMLDivElement>(null);
  const [bar, setBar] = useState({ show: false, size: 0, at: 0, up: false, down: false });
  const [scrolling, setScrolling] = useState(false);
  const [dragging, setDragging] = useState(false);
  const idle = useRef(0);

  const setView = useCallback(
    (el: HTMLDivElement | null) => {
      view.current = el;
      if (typeof viewRef === 'function') viewRef(el);
      else if (viewRef) (viewRef as { current: HTMLDivElement | null }).current = el;
    },
    [viewRef],
  );

  // Where the thumb goes, from where the view is scrolled to - and whether there is anything to scroll at all.
  const measure = useCallback(() => {
    const el = view.current;
    if (!el) return;
    const { scrollTop, scrollHeight, clientHeight } = el;
    const over = scrollHeight - clientHeight;
    const trackH = track.current?.clientHeight ?? clientHeight;
    if (over <= 1) {
      setBar(b => (b.show || b.up || b.down ? { show: false, size: 0, at: 0, up: false, down: false } : b));
      return;
    }
    const size = Math.round(Math.max(MIN_THUMB, (clientHeight / scrollHeight) * trackH));
    const at = Math.round((scrollTop / over) * (trackH - size));
    const up = scrollTop > 1;
    const down = scrollTop < over - 1;
    // (only a real change re-renders: this runs after every render, so a fresh object each time would never settle)
    setBar(b => (b.show && b.size === size && b.at === at && b.up === up && b.down === down ? b : { show: true, size, at, up, down }));
  }, []);

  useLayoutEffect(measure);
  useEffect(() => {
    const el = view.current;
    if (!el) return;
    // The view changes size with the panel; its content with what is in it.
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    for (const child of Array.from(el.children)) ro.observe(child);
    const mo = new MutationObserver(() => {
      for (const child of Array.from(el.children)) ro.observe(child);
      measure();
    });
    mo.observe(el, { childList: true });
    return () => {
      ro.disconnect();
      mo.disconnect();
    };
  }, [measure]);
  useEffect(() => () => window.clearTimeout(idle.current), []);

  const onScroll = () => {
    measure();
    setScrolling(true);
    window.clearTimeout(idle.current);
    idle.current = window.setTimeout(() => setScrolling(false), IDLE_MS);
  };

  // Drag the thumb: the view follows it, one to one along the track.
  const onThumbDown = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = view.current;
    const tr = track.current;
    if (!el || !tr || e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    const startY = e.clientY;
    const startTop = el.scrollTop;
    const ratio = (el.scrollHeight - el.clientHeight) / Math.max(1, tr.clientHeight - bar.size);
    setDragging(true);
    const move = (ev: PointerEvent) => {
      el.scrollTop = startTop + (ev.clientY - startY) * ratio;
    };
    const up = () => {
      setDragging(false);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  // A click on the track beside the thumb pages that way.
  const onTrackDown = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = view.current;
    const tr = track.current;
    if (!el || !tr || e.button !== 0) return;
    e.preventDefault();
    const y = e.clientY - tr.getBoundingClientRect().top;
    const dir = y < bar.at ? -1 : 1;
    el.scrollBy({ top: dir * el.clientHeight * 0.85, behavior: 'smooth' });
  };

  const fadeTop = fade && bar.up ? 18 : 0;
  const fadeBottom = fade && bar.down ? 18 : 0;
  return (
    <div {...rootAttrs} ref={rootRef} className={`sc-scrollarea ${className}`} style={style} data-overflow={bar.show} data-scrolling={scrolling || dragging} data-dragging={dragging}>
      <div
        ref={setView}
        role={role}
        className={`sc-scrollarea__view ${viewClassName}`}
        onScroll={onScroll}
        style={{ ...viewStyle, ['--sa-fade-top' as string]: `${fadeTop}px`, ['--sa-fade-bottom' as string]: `${fadeBottom}px` }}
      >
        {children}
      </div>
      <div ref={track} className="sc-scrollarea__track" data-show={bar.show} onPointerDown={onTrackDown} aria-hidden>
        <div className="sc-scrollarea__thumb" style={{ height: bar.size, transform: `translateY(${bar.at}px)` }} onPointerDown={onThumbDown} />
      </div>
    </div>
  );
}
