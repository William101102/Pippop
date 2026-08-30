import { useCallback, useState } from 'react';
import { loadFriendsBundle, respondFriendRequest, sendFriendRequest } from '../services/friends';
import { searchProfiles } from '../services/profiles';
import type { Friend, FriendRequest, Profile } from '../types';

export function useFriends(meId: string | undefined) {
  const [friends, setFriends] = useState<Friend[]>([]);
  const [requests, setRequests] = useState<FriendRequest[]>([]);
  const [sentIds, setSentIds] = useState<Set<string>>(new Set());
  const [searchResults, setSearchResults] = useState<Profile[]>([]);

  const reload = useCallback(async () => {
    if (!meId) return;
    const bundle = await loadFriendsBundle(meId);
    setFriends(bundle.friends);
    setRequests(bundle.requests);
    setSentIds(bundle.sentIds);
  }, [meId]);

  const search = useCallback(async (query: string) => {
    if (!meId) return;
    const rows = await searchProfiles(meId, query);
    setSearchResults(rows);
  }, [meId]);

  const sendRequest = useCallback(async (targetId: string) => {
    if (!meId) return;
    setSentIds((prev) => new Set(prev).add(targetId));
    try {
      await sendFriendRequest(meId, targetId);
    } catch (e) {
      setSentIds((prev) => {
        const next = new Set(prev);
        next.delete(targetId);
        return next;
      });
      throw e;
    }
  }, [meId]);

  const respond = useCallback(async (relId: string, status: 'accepted' | 'declined') => {
    await respondFriendRequest(relId, status);
    await reload();
  }, [reload]);

  const patchFriendLocation = useCallback((userId: string, location: Friend['location']) => {
    setFriends((prev) => prev.map((f) => (f.id === userId ? { ...f, location: location ?? null } : f)));
  }, []);

  return {
    friends,
    requests,
    sentIds,
    searchResults,
    reload,
    search,
    sendRequest,
    respond,
    patchFriendLocation,
    setFriends,
  };
}
