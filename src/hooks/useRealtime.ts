import { useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { Highlight, MapReaction, Message, PlaceEvent } from '../types';

export function useRealtime(opts: {
  meId?: string;
  onFriendsChange: () => void;
  onFriendLocation: (userId: string, row: Record<string, unknown> | null) => void;
  onMessage: (msg: Message) => void;
  onReaction: (reaction: MapReaction) => void;
  onPlaceEvent: (event: PlaceEvent) => void;
  onHighlight?: (highlight: Highlight) => void;
}) {
  const { meId, onFriendsChange, onFriendLocation, onMessage, onReaction, onPlaceEvent, onHighlight } = opts;

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
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'map_reactions' }, (payload) => {
        const reaction = payload.new as MapReaction;
        // RLS already limits what is delivered, but own reactions echo back.
        if (reaction.target_id !== meId) return;
        onReaction(reaction);
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'place_events' }, (payload) => {
        const event = payload.new as PlaceEvent;
        if (event.user_id === meId) return;
        onPlaceEvent(event);
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'highlights' }, (payload) => {
        const highlight = payload.new as Highlight;
        if (highlight.user_id === meId) return;
        onHighlight?.(highlight);
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [meId, onFriendsChange, onFriendLocation, onMessage, onReaction, onPlaceEvent, onHighlight]);
}
