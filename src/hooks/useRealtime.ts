import { useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { Message } from '../types';

export function useRealtime(opts: {
  meId?: string;
  onFriendsChange: () => void;
  onFriendLocation: (userId: string, row: Record<string, unknown> | null) => void;
  onMessage: (msg: Message) => void;
}) {
  const { meId, onFriendsChange, onFriendLocation, onMessage } = opts;

  useEffect(() => {
    if (!meId) return;
    const channel = supabase
      .channel('pinpop-app')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'locations' }, (payload) => {
        const row = (payload.new || payload.old) as Record<string, unknown> | null;
        if (!row || row.user_id === meId) return;
        onFriendLocation(String(row.user_id), payload.new as Record<string, unknown> | null);
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'friendships' }, () => {
        onFriendsChange();
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, (payload) => {
        onMessage(payload.new as Message);
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [meId, onFriendsChange, onFriendLocation, onMessage]);
}
