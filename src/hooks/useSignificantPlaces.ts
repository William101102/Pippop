import { useCallback, useEffect, useRef, useState } from 'react';
import {
  detectSignificantPlaces,
  placesToPersist,
  type SignificantPlace,
} from '../lib/places';
import {
  appendLocationHistory,
  deleteSignificantPlaces,
  loadLocationHistory,
  loadSignificantPlaces,
  upsertSignificantPlaces,
} from '../services/places';

/**
 * Records throttled location fixes into location_history and periodically
 * re-runs overnight / home / work detection. All data is private to the
 * signed-in user (enforced by RLS in 202608300003_significant_places.sql).
 */
export function useSignificantPlaces(userId: string | undefined, enabled: boolean) {
  const [places, setPlaces] = useState<SignificantPlace[]>([]);
  const lastFixRef = useRef<{ lat: number; lng: number; at: number } | null>(null);
  const lastDetectRef = useRef(0);

  const recordFix = useCallback(
    async (lat: number, lng: number, at: string) => {
      if (!userId) return;
      // Throttle: min 30 s and min ~50 m since the last recorded fix.
      const last = lastFixRef.current;
      if (last && Date.now() - last.at < 30_000) return;
      if (last && Math.hypot((lat - last.lat) * 111_000, (lng - last.lng) * 111_000) < 50) return;
      lastFixRef.current = { lat, lng, at: Date.now() };
      try {
        await appendLocationHistory(userId, lat, lng, at);
      } catch {
        // history recording is best-effort
      }
      // Re-detect at most every 5 minutes.
      if (Date.now() - lastDetectRef.current < 5 * 60_000) return;
      lastDetectRef.current = Date.now();
      try {
        const points = await loadLocationHistory(userId);
        const detected = detectSignificantPlaces(points);
        await deleteSignificantPlaces(userId, ['overnight', 'home', 'work']);
        await upsertSignificantPlaces(userId, placesToPersist(detected));
        setPlaces(await loadSignificantPlaces(userId));
      } catch {
        // detection is best-effort
      }
    },
    [userId],
  );

  const reload = useCallback(async () => {
    if (!userId) return;
    setPlaces(await loadSignificantPlaces(userId));
  }, [userId]);

  useEffect(() => {
    if (!userId || !enabled) {
      setPlaces([]);
      return;
    }
    reload().catch(() => undefined);
  }, [userId, enabled, reload]);

  return { places, recordFix, reload };
}
