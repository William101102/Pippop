import { supabase } from '../lib/supabase';
import type { Friend, FriendRequest, FriendshipRow, LiveLocation, Profile } from '../types';

async function fetchLocationsForUsers(userIds: string[]): Promise<LiveLocation[]> {
  if (!userIds.length) return [];

  const { data: viewData, error: viewError } = await supabase
    .from('friend_locations')
    .select('*')
    .in('user_id', userIds);

  if (!viewError && viewData) return viewData as LiveLocation[];

  const { data, error } = await supabase.from('locations').select('*').in('user_id', userIds);
  if (error) throw error;
  return (data || []) as LiveLocation[];
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
    const [{ data: profiles }, locations] = await Promise.all([
      supabase.from('profiles').select('*').in('id', friendIds),
      fetchLocationsForUsers(friendIds),
    ]);
    friends = ((profiles || []) as Profile[]).map((p) => ({
      ...p,
      location: locations.find((l) => l.user_id === p.id) || null,
    }));
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
