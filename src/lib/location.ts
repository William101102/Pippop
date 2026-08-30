import { BackgroundGeolocation } from './backgroundGeolocation';
import { isNative } from './native';

export interface Fix {
  lat: number;
  lng: number;
  accuracy: number | null;
  speed: number | null;
}

/** Ignore jitter below this unless enough time has passed anyway. */
export const MIN_MOVE_METRES = 25;
const MIN_INTERVAL_MS = 45_000;

export function metresBetween(aLat: number, aLng: number, bLat: number, bLng: number) {
  const R = 6_371_000;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * Every persisted fix fans out to all friends over realtime, and background
 * watchers fire far more often than the map needs, so drop the fixes that say
 * nothing new.
 */
export function createFixGate() {
  let last: { at: number; lat: number; lng: number } | null = null;
  return {
    shouldPersist(fix: Fix) {
      if (!last) return true;
      const moved = metresBetween(last.lat, last.lng, fix.lat, fix.lng);
      return moved >= MIN_MOVE_METRES || Date.now() - last.at >= MIN_INTERVAL_MS;
    },
    commit(fix: Fix) {
      last = { at: Date.now(), lat: fix.lat, lng: fix.lng };
    },
  };
}

/**
 * Watches position on whichever platform is running. The native watcher keeps
 * reporting while the app is backgrounded, which is the reason to ship outside
 * the browser at all; the browser can only report while it is on screen.
 */
export function watchLocation(
  onFix: (fix: Fix) => void,
  onDenied?: () => void,
): () => void {
  if (isNative) {
    let watcherId: string | null = null;
    let cancelled = false;

    void (async () => {
      const id = await BackgroundGeolocation.addWatcher(
        {
          backgroundMessage: '正在与好友分享你的位置',
          backgroundTitle: 'Pinpop 正在使用你的位置',
          requestPermissions: true,
          stale: false,
          distanceFilter: MIN_MOVE_METRES,
        },
        (position, error) => {
          if (error) {
            if (error.code === 'NOT_AUTHORIZED') onDenied?.();
            return;
          }
          if (!position) return;
          onFix({
            lat: position.latitude,
            lng: position.longitude,
            accuracy: position.accuracy,
            speed: position.speed,
          });
        },
      );
      if (cancelled) await BackgroundGeolocation.removeWatcher({ id });
      else watcherId = id;
    })().catch(() => onDenied?.());

    return () => {
      cancelled = true;
      const id = watcherId;
      if (!id) return;
      void BackgroundGeolocation.removeWatcher({ id }).catch(() => undefined);
    };
  }

  if (!navigator.geolocation) return () => undefined;
  const watch = navigator.geolocation.watchPosition(
    (position) =>
      onFix({
        lat: position.coords.latitude,
        lng: position.coords.longitude,
        accuracy: position.coords.accuracy,
        speed: position.coords.speed,
      }),
    (error) => {
      if (error.code === error.PERMISSION_DENIED) onDenied?.();
    },
    { enableHighAccuracy: true, maximumAge: 8000, timeout: 20000 },
  );
  return () => navigator.geolocation.clearWatch(watch);
}
