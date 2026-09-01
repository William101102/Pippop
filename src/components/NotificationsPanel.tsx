import { Check, Heart, MapPin, MessageCircle, UserPlus, X } from 'lucide-react';
import { Avatar } from './Avatar';
import { timeAgo } from '../lib/format';
import type { Friend, FriendRequest, MapReaction, Message, PlaceEvent } from '../types';

export interface UnreadPreview {
  friend: Friend;
  count: number;
  last?: Message;
}

interface Props {
  requests: FriendRequest[];
  unreadPreviews: UnreadPreview[];
  reactions: MapReaction[];
  placeEvents: PlaceEvent[];
  friends: Friend[];
  busyIds: Set<string>;
  onRespond: (relId: string, status: 'accepted' | 'declined') => void;
  onOpenChat: (friendId: string) => void;
  onFocusEvent: (lat: number, lng: number) => void;
}

export function NotificationsPanel({
  requests, unreadPreviews, reactions, placeEvents, friends, busyIds,
  onRespond, onOpenChat, onFocusEvent,
}: Props) {
  const nameOf = (userId: string) =>
    friends.find((f) => f.id === userId)?.display_name || 'friend';

  const empty =
    requests.length === 0 &&
    unreadPreviews.length === 0 &&
    reactions.length === 0 &&
    placeEvents.length === 0;

  if (empty) {
    return (
      <div className="empty-state">
        <span className="empty-art">🔔</span>
        <b>You're all caught up</b>
        <p>Friend requests, waves, and check-ins will show up here.</p>
      </div>
    );
  }

  return (
    <div className="notifications-panel">
      {requests.length > 0 && (
        <>
          <div className="eyebrow"><UserPlus size={12} /> Friend requests</div>
          <div className="friend-list">
            {requests.map((request) => (
              <div className="friend-row static" key={request.relId}>
                <Avatar profile={request.profile} />
                <div><b>{request.profile.display_name}</b><small>@{request.profile.username}</small></div>
                <div className="request-actions">
                  <button
                    type="button" className="tiny solid" aria-label="Accept"
                    disabled={busyIds.has(request.relId)}
                    onClick={() => onRespond(request.relId, 'accepted')}
                  ><Check size={15} /></button>
                  <button
                    type="button" className="tiny ghost" aria-label="Decline"
                    disabled={busyIds.has(request.relId)}
                    onClick={() => onRespond(request.relId, 'declined')}
                  ><X size={15} /></button>
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {unreadPreviews.length > 0 && (
        <>
          <div className="eyebrow"><MessageCircle size={12} /> Unread messages</div>
          <div className="friend-list">
            {unreadPreviews.map(({ friend, count, last }) => (
              <button className="friend-row" key={friend.id} type="button" onClick={() => onOpenChat(friend.id)}>
                <Avatar profile={friend} showStatus />
                <div><b>{friend.display_name}</b><small>{last?.body || 'New message'}</small></div>
                <span className="friend-meta">
                  <span className="badge">{count}</span>
                  {last && <small>{timeAgo(last.created_at)}</small>}
                </span>
              </button>
            ))}
          </div>
        </>
      )}

      {reactions.length > 0 && (
        <>
          <div className="eyebrow"><Heart size={12} /> Reactions received</div>
          <div className="friend-list">
            {reactions.slice(0, 8).map((reaction) => (
              <div className="friend-row static" key={reaction.id}>
                <span className="avatar reaction-avatar">{reaction.emoji}</span>
                <div>
                  <b>{nameOf(reaction.sender_id)}</b>
                  <small>sent you {reaction.emoji}</small>
                </div>
                <span className="friend-meta"><small>{timeAgo(reaction.created_at)}</small></span>
              </div>
            ))}
          </div>
        </>
      )}

      {placeEvents.length > 0 && (
        <>
          <div className="eyebrow"><MapPin size={12} /> Friend activity</div>
          <div className="friend-list">
            {placeEvents.slice(0, 10).map((event) => (
              <button
                className="friend-row"
                key={event.id}
                type="button"
                disabled={event.lat == null || event.lng == null}
                onClick={() => event.lat != null && event.lng != null && onFocusEvent(event.lat, event.lng)}
              >
                <span className="avatar place-avatar">{event.kind === 'arrive' ? '📍' : '🚶'}</span>
                <div>
                  <b>{nameOf(event.user_id)}</b>
                  <small>{event.kind === 'arrive' ? 'arrived at' : 'left'} {event.label || 'a place'}</small>
                </div>
                <span className="friend-meta"><small>{timeAgo(event.created_at)}</small></span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
