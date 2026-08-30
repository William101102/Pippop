import { Preferences } from '@capacitor/preferences';
import { isNative } from './native';
import type { Friend } from '../types';

/**
 * Feeds the home screen widget.
 *
 * The widget process cannot reach Supabase (no session, and it gets only a few
 * seconds to render), so the app writes a snapshot that the widget reads. The
 * App Group configured in ios-setup/WIDGET.md is what makes the same key
 * visible to both processes.
 */
const WIDGET_KEY = 'widget_friends';
const WIDGET_GROUP = 'group.com.pinpop.app';
/** Keep the payload small: a widget only has room for a handful of faces. */
const MAX_FRIENDS = 4;

export interface WidgetFriend {
  name: string;
  emoji: string;
  status: string;
  /** Minutes since their last fix, so the widget can label staleness itself. */
  ageMinutes: number | null;
}

export async function publishWidgetSnapshot(friends: Friend[]) {
  if (!isNative) return;

  // Best friends first, matching the order the app itself shows.
  const payload: WidgetFriend[] = friends.slice(0, MAX_FRIENDS).map((friend) => ({
    name: friend.display_name || `@${friend.username}`,
    emoji: friend.status_emoji || '📍',
    status: friend.status_text || '',
    ageMinutes: friend.location
      ? Math.round((Date.now() - new Date(friend.location.updated_at).getTime()) / 60_000)
      : null,
  }));

  try {
    await Preferences.configure({ group: WIDGET_GROUP });
    await Preferences.set({
      key: WIDGET_KEY,
      value: JSON.stringify({ friends: payload, updatedAt: new Date().toISOString() }),
    });
  } catch {
    // The widget simply shows its placeholder if this never lands.
  }
}
