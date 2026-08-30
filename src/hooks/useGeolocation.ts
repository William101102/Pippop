import { useEffect, useRef, useState } from 'react';
import { getMyLastLocation, upsertMyLocation } from '../services/locations';
import type { GhostMode, LiveLocation } from '../types';

export function useGeolocation(
  userId: string | undefined,
  enabled: boolean,
  ghostMode: GhostMode,
) {
  const [location, setLocation] = useState<LiveLocation | null>(null);
  const watchRef = useRef<number | null>(null);

  useEffect(() => {
    if (!userId || !enabled) return;
    getMyLastLocation(userId).then((row) => {
      if (row) setLocation(row as LiveLocation);
    });
  }, [userId, enabled]);

  useEffect(() => {
    if (!userId || !enabled || !navigator.geolocation) return;
    watchRef.current = navigator.geolocation.watchPosition(
      async (pos) => {
        const next: LiveLocation = {
          user_id: userId,
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
          speed: pos.coords.speed,
          updated_at: new Date().toISOString(),
        };
        setLocation(next);
        if (ghostMode !== 'frozen') {
          await upsertMyLocation(next);
        }
      },
      () => undefined,
      { enableHighAccuracy: true, maximumAge: 8000, timeout: 20000 },
    );
    return () => {
      if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current);
    };
  }, [userId, enabled, ghostMode]);

  return { location, setLocation };
}
