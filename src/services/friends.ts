import { supabase } from '../lib/supabase';
import type { Friend, FriendRequest, LiveLocation, Profile } from '../types';

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

export async function sendFriendRequest(meId: string, targetId: string) {
  const { error } = await supabase.from('friendships').insert({ requester_id: meId, addressee_id: targetId });
  if (error) throw error;
}

export async function respondFriendRequest(relId: string, status: 'accepted' | 'declined') {
  const { error } = await supabase.from('friendships').update({ status }).eq('id', relId);
  if (error) throw error;
}

export async function fetchFriendLocation(userId: string) {
  const rows = await fetchLocationsForUsers([userId]);
  return rows[0] || null;
}
