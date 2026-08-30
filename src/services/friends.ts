import { supabase } from '../lib/supabase';
import { loadBestFriendIds } from './social';
import type { Friend, FriendRequest, FriendshipRow, LiveLocation, Profile } from '../types';

/**
 * friend_locations applies Ghost Mode masking, so it is the preferred source.
 * A misconfigured view returns zero rows rather than an error though, which used
 * to leave every friend stuck on "暂无位置", so fall back to the table for
 * anyone the view omitted. That cannot leak masked coordinates: the table's
 * select policy only exposes friends who are in 'precise' mode anyway.
 */
async function fetchLocationsForUsers(userIds: string[]): Promise<LiveLocation[]> {
  if (!userIds.length) return [];

  const [view, table] = await Promise.all([
    supabase.from('friend_locations').select('*').in('user_id', userIds),
    supabase.from('locations').select('*').in('user_id', userIds),
  ]);

  if (view.error && table.error) throw view.error;

  const byUser = new Map<string, LiveLocation>();
  for (const row of (table.data || []) as LiveLocation[]) byUser.set(row.user_id, row);
  for (const row of (view.data || []) as LiveLocation[]) {
    byUser.set(row.user_id, {
      ...row,
      privacy_mode: row.privacy_mode,
    });
  }
  return [...byUser.values()];
}

export async function loadFriendsBundle(meId: string) {
  const { data: rels, error } = await supabase
    .from('friendships')
    .select('*')
    .or(`requester_id.eq.${meId},addressee_id.eq.${meId}`);
  if (error) throw error;

  const all = rels || [];
  const accepted = all.filter((r) => r.status === 'accepted');
  const incoming = all.filter((r) => r.status === 'pending' && r.addressee_id === meId);
  const outgoing = all.filter((r) => r.status === 'pending' && r.requester_id === meId);
  const sentIds = new Set(outgoing.map((r) => r.addressee_id));

  let requests: FriendRequest[] = [];
  if (incoming.length) {
    const reqIds = incoming.map((r) => r.requester_id);
    const { data: reqProfiles } = await supabase.from('profiles').select('*').in('id', reqIds);
    requests = incoming
      .map((r) => ({ relId: r.id, profile: (reqProfiles || []).find((p) => p.id === r.requester_id) }))
      .filter((x): x is FriendRequest => Boolean(x.profile)) as FriendRequest[];
  }

  const friendIds = accepted.map((r) => (r.requester_id === meId ? r.addressee_id : r.requester_id));
  let friends: Friend[] = [];
  if (friendIds.length) {
    const [{ data: profiles }, locations, bestFriendIds] = await Promise.all([
      supabase.from('profiles').select('*').in('id', friendIds),
      fetchLocationsForUsers(friendIds),
      loadBestFriendIds(meId),
    ]);
    // The streak lives on the friendship row, which is already loaded above.
    const streakByFriend = new Map<string, number>();
    for (const rel of accepted as FriendshipRow[]) {
      const other = rel.requester_id === meId ? rel.addressee_id : rel.requester_id;
      streakByFriend.set(other, rel.streak_days ?? 0);
    }
    friends = ((profiles || []) as Profile[]).map((p) => {
      const location = locations.find((l) => l.user_id === p.id) || null;
      return {
        ...p,
        location,
        ghost_mode: location?.privacy_mode,
        streak_days: streakByFriend.get(p.id) ?? 0,
        is_best_friend: bestFriendIds.has(p.id),
      };
    });
    // Best friends first, then the people you actually talk to.
    friends.sort((a, b) => {
      if (a.is_best_friend !== b.is_best_friend) return a.is_best_friend ? -1 : 1;
      return (b.streak_days ?? 0) - (a.streak_days ?? 0);
    });
  }

  return { friends, requests, sentIds };
}

/**
 * Returns 'accepted' when the target had already invited us, so two people
 * adding each other pairs up instead of creating a second row for the same
 * relationship (which used to break the friendships_pair_unique index).
 */
export async function sendFriendRequest(meId: string, targetId: string) {
  const { data: existing } = await supabase
    .from('friendships')
    .select('id,requester_id,addressee_id,status')
    .or(
      `and(requester_id.eq.${meId},addressee_id.eq.${targetId}),` +
      `and(requester_id.eq.${targetId},addressee_id.eq.${meId})`,
    )
    .maybeSingle();

  if (existing) {
    const row = existing as FriendshipRow;
    if (row.status === 'accepted') return 'already_friends' as const;
    // They invited us first: accepting is what the user actually meant.
    if (row.addressee_id === meId) {
      await respondFriendRequest(row.id, 'accepted');
      return 'accepted' as const;
    }
    if (row.status === 'pending') return 'already_sent' as const;
    // A previously declined request can be revived.
    const { error: reviveError } = await supabase
      .from('friendships')
      .update({ status: 'pending' })
      .eq('id', row.id);
    if (reviveError) throw reviveError;
    return 'sent' as const;
  }

  const { error } = await supabase
    .from('friendships')
    .insert({ requester_id: meId, addressee_id: targetId, status: 'pending' });
  if (error) throw error;
  return 'sent' as const;
}

export async function respondFriendRequest(relId: string, status: 'accepted' | 'declined') {
  const { error } = await supabase.from('friendships').update({ status }).eq('id', relId);
  if (error) throw error;
}

export async function fetchFriendLocation(userId: string) {
  const rows = await fetchLocationsForUsers([userId]);
  return rows[0] || null;
}
