import { useCallback, useEffect, useRef, useState } from 'react';
import { haptic } from '../lib/native';

/** Drag further than this and the release is treated as a dismiss. */
const DISMISS_PX = 110;
/** Below this the gesture is a tap, not a drag. */
const SLOP_PX = 6;

interface Options {
  onDismiss: () => void;
  /** Sheets are full height on desktop, where dragging them makes no sense. */
  enabled: boolean;
}

/**
 * Drag-to-dismiss for the bottom sheet, which is the single biggest tell that
 * something is an app rather than a page.
 *
 * Only downward drags that start on the grab handle move the sheet, so the
 * panels inside keep their own scrolling. Pointer events cover touch and mouse
 * without a second code path.
 */
export function useDraggableSheet({ onDismiss, enabled }: Options) {
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
    // the sheet already being at its top rather than as a broken gesture.
    setOffset(delta >= 0 ? delta : delta / 5);
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
      style: offset ? { transform: `translateY(${offset}px)` } : undefined,
      className: dragging ? 'dragging' : '',
    },
  };
}
