import { supabase } from '../lib/supabase';
import type { MapReaction, PlaceEvent, PlaceEventKind } from '../types';

/** A table the user has not migrated yet should degrade, not crash the panel. */
const MISSING_TABLE = '42P01';

export async function loadBestFriendIds(meId: string): Promise<Set<string>> {
  const { data, error } = await supabase
    .from('best_friends')
    .select('friend_id')
    .eq('owner_id', meId);
  if (error) {
    if (error.code === MISSING_TABLE) return new Set();
    throw error;
  }
  return new Set((data || []).map((row) => (row as { friend_id: string }).friend_id));
}

export async function setBestFriend(meId: string, friendId: string, pinned: boolean) {
  if (pinned) {
    const { error } = await supabase
      .from('best_friends')
      .upsert({ owner_id: meId, friend_id: friendId }, { onConflict: 'owner_id,friend_id' });
    if (error) throw error;
    return;
  }
  const { error } = await supabase
    .from('best_friends')
    .delete()
    .eq('owner_id', meId)
    .eq('friend_id', friendId);
  if (error) throw error;
}

export interface Throwable { emoji: string; label: string }

/** The full "throw something at a friend" catalog — reuses map_reactions as-is
 *  (the emoji column is free text), so growing this list needs no schema change. */
export const THROWABLES: Throwable[] = [
  { emoji: '🎂', label: 'Cake' },
  { emoji: '🎉', label: 'Cheers' },
  { emoji: '🌹', label: 'Rose' },
  { emoji: '❤️', label: 'Love' },
  { emoji: '🍕', label: 'Pizza' },
  { emoji: '☕', label: 'Coffee' },
  { emoji: '🍺', label: 'Beer' },
  { emoji: '🎁', label: 'Gift' },
  { emoji: '💦', label: 'Splash' },
  { emoji: '🔥', label: 'Fire' },
  { emoji: '😂', label: 'LOL' },
  { emoji: '👀', label: 'Saw you' },
  { emoji: '😴', label: 'Sleepy' },
  { emoji: '🤙', label: 'Hey' },
];

export const REACTION_EMOJI = THROWABLES.map((t) => t.emoji);

export async function sendReaction(meId: string, targetId: string, emoji: string) {
  const { error } = await supabase
    .from('map_reactions')
    .insert({ sender_id: meId, target_id: targetId, emoji });
  if (error) {
    if (error.code === MISSING_TABLE) {
      throw new Error('The reactions feature is not installed on the server yet — run setup.sql first');
    }
    throw error;
  }
}

/** Reactions aimed at me that have not expired, newest first. */
export async function loadMyReactions(meId: string): Promise<MapReaction[]> {
  const { data, error } = await supabase
    .from('map_reactions')
    .select('*')
    .eq('target_id', meId)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(30);
  if (error) {
    if (error.code === MISSING_TABLE) return [];
    throw error;
  }
  return (data || []) as MapReaction[];
}

export async function recordPlaceEvent(
  meId: string,
  kind: PlaceEventKind,
  label: string,
  lat?: number,
  lng?: number,
) {
  const { error } = await supabase
    .from('place_events')
    .insert({ user_id: meId, kind, label, lat, lng });
  // Arrival notices are a nicety; never surface a failure to the user.
  if (error && error.code !== MISSING_TABLE) throw error;
}

/** Friends' recent arrivals and departures for the notifications feed. */
export async function loadPlaceEvents(hours = 12): Promise<PlaceEvent[]> {
  const since = new Date(Date.now() - hours * 3600_000).toISOString();
  const { data, error } = await supabase
    .from('place_events')
    .select('*')
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(40);
  if (error) {
    if (error.code === MISSING_TABLE) return [];
    throw error;
  }
  return (data || []) as PlaceEvent[];
}
