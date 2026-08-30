import { PushNotifications } from '@capacitor/push-notifications';
import { supabase } from './supabase';
import { isIOS, isNative } from './native';

/**
 * Registers this device for push and stores the APNs token against the user.
 *
 * Tokens rotate, and the same person can have several devices, so the token is
 * the primary key server side rather than the user. Returns a cleanup function.
 */
export async function registerPush(userId: string): Promise<() => void> {
  if (!isNative) return () => undefined;

  const listeners: { remove: () => void }[] = [];

  try {
    // Asking before the user has any friends would burn the one prompt iOS
    // gives us, so callers decide when this runs.
    let status = await PushNotifications.checkPermissions();
    if (status.receive === 'prompt' || status.receive === 'prompt-with-rationale') {
      status = await PushNotifications.requestPermissions();
    }
    if (status.receive !== 'granted') return () => undefined;

    const registration = await PushNotifications.addListener('registration', (token) => {
      void supabase
        .from('push_tokens')
        .upsert(
          {
            token: token.value,
            user_id: userId,
            platform: isIOS ? 'ios' : 'android',
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'token' },
        )
        .then(() => undefined);
    });
    listeners.push(registration);

    const failure = await PushNotifications.addListener('registrationError', () => {
      // Nothing actionable for the user; they simply get no pushes.
    });
    listeners.push(failure);

    await PushNotifications.register();
  } catch {
    // Push is an enhancement; never let it break sign-in.
  }

  return () => {
    for (const listener of listeners) listener.remove();
  };
}

/** Called on sign-out so a shared device stops receiving the old user's pushes. */
export async function unregisterPush(userId: string) {
  if (!isNative) return;
  try {
    await supabase.from('push_tokens').delete().eq('user_id', userId);
    await PushNotifications.removeAllListeners();
  } catch {
    // Best effort.
  }
}

/** Clears the springboard badge, which iOS otherwise leaves stuck. */
export async function clearPushBadge() {
  if (!isNative) return;
  try {
    await PushNotifications.removeAllDeliveredNotifications();
  } catch {
    // Best effort.
  }
}
