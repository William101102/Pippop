import { isNative, nativeShare } from './native';

export function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Invite links have to be openable by someone who does not have the app, and
 * inside the native shell location.origin is capacitor://localhost, so the
 * public web build is always the link target.
 */
export function inviteUrl(username: string) {
  const configured = import.meta.env.VITE_PUBLIC_APP_URL?.replace(/\/+$/, '');
  const base = configured
    ? `${configured}/`
    : isNative
      ? 'https://william101102.github.io/zenly-app/'
      : `${location.origin}${location.pathname}`;
  return `${base}?add=${encodeURIComponent(username)}`;
}

export function inviteText(username: string, displayName: string) {
  return `加我 Pinpop 好友 @${username}（${displayName}）\n${inviteUrl(username)}`;
}

export function friendShareText(username: string, displayName: string) {
  return `推荐你在 Pinpop 上加我的好友 @${username}（${displayName}）\n${inviteUrl(username)}`;
}

export async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    return ok;
  }
}

export async function shareText(title: string, text: string, url: string) {
  const native = await nativeShare(title, text, url);
  if (native !== 'unsupported') return native;

  if (navigator.share) {
    try {
      await navigator.share({ title, text, url });
      return 'shared' as const;
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') return 'cancelled' as const;
    }
  }
  await copyText(text);
  return 'copied' as const;
}
