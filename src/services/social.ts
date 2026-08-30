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

export const REACTION_EMOJI = ['❤️', '😂', '🔥', '👀', '🎉', '😴'];

export async function sendReaction(meId: string, targetId: string, emoji: string) {
  const { error } = await supabase
    .from('map_reactions')
    .insert({ sender_id: meId, target_id: targetId, emoji });
  if (error) {
    if (error.code === MISSING_TABLE) {
      throw new Error('服务端还没有安装表情功能，请先运行 setup.sql');
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
