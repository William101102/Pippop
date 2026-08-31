import { useCallback, useEffect, useRef, useState } from 'react';
import { haptic } from '../lib/native';

/** Drag further than this and the release is treated as a dismiss. */
const DISMISS_PX = 110;
/** Below this the gesture is a tap, not a drag. */
const SLOP_PX = 6;
/**
 * Upward drags get resistance (delta / 5) rather than a hard stop, but with
 * no ceiling that resistance still lets a long enough drag push the sheet up
 * past the phone's status bar / notch. Cap how far it can rise so it always
 * reads as "already at the top" instead of drifting off-screen.
 */
const MAX_PULL_UP_PX = 40;

interface Options {
  onDismiss: () => void;
  /** Sheets are full height on desktop, where dragging them makes no sense. */
  enabled: boolean;
  /**
   * Any transform the sheet always needs (e.g. PersonCard's `translateX(-50%)`
   * horizontal centering). The drag offset is appended to this rather than
   * replacing it — an inline `style.transform` from the drag would otherwise
   * clobber the base transform entirely, which is what made PersonCard jump
   * sideways the instant a drag started.
   */
  baseTransform?: string;
}

/**
 * Drag-to-dismiss for the bottom sheet, which is the single biggest tell that
 * something is an app rather than a page.
 *
 * Only downward drags that start on the grab handle move the sheet, so the
 * panels inside keep their own scrolling. Pointer events cover touch and mouse
 * without a second code path.
 */
export function useDraggableSheet({ onDismiss, enabled, baseTransform = '' }: Options) {
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);
  const startRef = useRef<{ y: number; pointerId: number } | null>(null);
  const passedSlop = useRef(false);

  // A sheet that swaps content while dragging should not stay pushed down.
  const reset = useCallback(() => {
    startRef.current = null;
    passedSlop.current = false;
    setDragging(false);
    setOffset(0);
  }, []);

  useEffect(() => {
    if (!enabled) reset();
  }, [enabled, reset]);

  const onPointerDown = useCallback(
    (event: React.PointerEvent) => {
      if (!enabled) return;
      startRef.current = { y: event.clientY, pointerId: event.pointerId };
      passedSlop.current = false;
      event.currentTarget.setPointerCapture?.(event.pointerId);
    },
    [enabled],
  );

  const onPointerMove = useCallback((event: React.PointerEvent) => {
    const start = startRef.current;
    if (!start || start.pointerId !== event.pointerId) return;
    const delta = event.clientY - start.y;

    if (!passedSlop.current) {
      if (Math.abs(delta) < SLOP_PX) return;
      passedSlop.current = true;
      setDragging(true);
    }

    // Upward drags get heavy resistance instead of a hard stop, which reads as
    // the sheet already being at its top rather than as a broken gesture —
    // and that resistance is capped so a long drag can't push it past the
    // top of the screen either.
    setOffset(delta >= 0 ? delta : Math.max(delta / 5, -MAX_PULL_UP_PX));
  }, []);

  const onPointerUp = useCallback(
    (event: React.PointerEvent) => {
      const start = startRef.current;
      if (!start || start.pointerId !== event.pointerId) return;
      const delta = event.clientY - start.y;
      const wasDragging = passedSlop.current;
      reset();
      if (wasDragging && delta > DISMISS_PX) {
        haptic('light');
        onDismiss();
      }
    },
    [onDismiss, reset],
  );

  return {
    /** Spread onto the grab handle. */
    handleProps: {
      onPointerDown,
      onPointerMove,
      onPointerUp,
      onPointerCancel: onPointerUp,
    },
    /** Spread onto the sheet itself. */
    sheetProps: {
      style: offset ? { transform: `${baseTransform} translateY(${offset}px)`.trim() } : undefined,
      className: dragging ? 'dragging' : '',
    },
  };
}
