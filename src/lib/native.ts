import { Capacitor } from '@capacitor/core';
import { App as CapacitorApp } from '@capacitor/app';
import { BackgroundGeolocation } from './backgroundGeolocation';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';
import { Keyboard } from '@capacitor/keyboard';
import { Share } from '@capacitor/share';
import { SplashScreen } from '@capacitor/splash-screen';
import { Style as StatusBarStyle, StatusBar } from '@capacitor/status-bar';

export const isNative = Capacitor.isNativePlatform();
export const isIOS = Capacitor.getPlatform() === 'ios';

/**
 * Every native call is guarded rather than dynamically imported: the same
 * bundle also ships to GitHub Pages, where these plugins have web stubs that
 * reject instead of no-op'ing.
 */
async function quietly(run: () => Promise<unknown>) {
  if (!isNative) return;
  try {
    await run();
  } catch {
    // A missing capability must never break the interaction that triggered it.
  }
}

export function haptic(kind: 'light' | 'medium' | 'heavy' | 'select' | 'success' | 'warning') {
  void quietly(() => {
    switch (kind) {
      case 'select':
        return Haptics.selectionChanged();
      case 'success':
        return Haptics.notification({ type: NotificationType.Success });
      case 'warning':
        return Haptics.notification({ type: NotificationType.Warning });
      case 'heavy':
        return Haptics.impact({ style: ImpactStyle.Heavy });
      case 'medium':
        return Haptics.impact({ style: ImpactStyle.Medium });
      default:
        return Haptics.impact({ style: ImpactStyle.Light });
    }
  });
}

/** Dark glyphs, because the map and sheets are light in both themes. */
export async function initNativeShell() {
  await quietly(() => StatusBar.setStyle({ style: StatusBarStyle.Light }));
  await quietly(() => StatusBar.setOverlaysWebView({ overlay: true }));
  await quietly(() => Keyboard.setAccessoryBarVisible({ isVisible: false }));
}

/** Called once the map has a first frame so the splash never hides an empty map. */
export function dismissSplash() {
  void quietly(() => SplashScreen.hide({ fadeOutDuration: 220 }));
}

/**
 * Native share sheet when available. Returns the same shape as the web helper so
 * callers do not care which path ran.
 */
export async function nativeShare(title: string, text: string, url: string) {
  if (!isNative) return 'unsupported' as const;
  try {
    await Share.share({ title, text, url, dialogTitle: title });
    return 'shared' as const;
  } catch (error) {
    // The iOS sheet reports a plain cancellation as an error.
    const message = error instanceof Error ? error.message.toLowerCase() : '';
    if (message.includes('cancel')) return 'cancelled' as const;
    return 'unsupported' as const;
  }
}

/**
 * Friends' pins go stale while the app is suspended, so callers use this to
 * refetch on resume the way a native app would.
 */
export function onAppResume(callback: () => void) {
  if (!isNative) {
    const onVisible = () => {
      if (document.visibilityState === 'visible') callback();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }

  const handle = CapacitorApp.addListener('appStateChange', ({ isActive }) => {
    if (isActive) callback();
  });
  return () => {
    void handle.then((listener) => listener.remove());
  };
}

/** Lets iOS users reach Settings after denying location, instead of dead-ending. */
export async function openAppSettings() {
  await quietly(() => BackgroundGeolocation.openSettings());
}
