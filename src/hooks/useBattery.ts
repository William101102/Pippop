import { useEffect, useState } from 'react';
import { updateBattery } from '../services/profiles';

interface BatteryManager extends EventTarget {
  level: number;
  charging: boolean;
}

type NavigatorWithBattery = Navigator & { getBattery?: () => Promise<BatteryManager> };

export interface BatteryState {
  level: number;
  charging: boolean;
}

/**
 * Mirrors the device battery onto the profile so friends see it on the map.
 * The Battery Status API is Chromium-only, so absence is not an error.
 */
export function useBattery(userId: string | undefined) {
  const [battery, setBattery] = useState<BatteryState | null>(null);

  useEffect(() => {
    if (!userId) {
      setBattery(null);
      return;
    }
    const getBattery = (navigator as NavigatorWithBattery).getBattery;
    if (!getBattery) return;

    let cancelled = false;
    let manager: BatteryManager | null = null;

    const publish = () => {
      if (!manager || cancelled) return;
      const next = { level: manager.level, charging: manager.charging };
      setBattery(next);
      updateBattery(userId, next.level, next.charging).catch(() => undefined);
    };

    getBattery.call(navigator).then((result) => {
      if (cancelled) return;
      manager = result;
      publish();
      manager.addEventListener('levelchange', publish);
      manager.addEventListener('chargingchange', publish);
    }).catch(() => undefined);

    return () => {
      cancelled = true;
      manager?.removeEventListener('levelchange', publish);
      manager?.removeEventListener('chargingchange', publish);
    };
  }, [userId]);

  return battery;
}
