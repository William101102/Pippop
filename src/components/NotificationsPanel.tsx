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
    friends.find((f) => f.id === userId)?.display_name || '朋友';

  const empty =
    requests.length === 0 &&
    unreadPreviews.length === 0 &&
    reactions.length === 0 &&
    placeEvents.length === 0;

  if (empty) return <p className="muted empty-hint">现在没有新通知 🎉</p>;

  return (
    <div className="notifications-panel">
      {requests.length > 0 && (
        <>
          <div className="eyebrow"><UserPlus size={12} /> 好友请求</div>
          <div className="friend-list">
            {requests.map((request) => (
              <div className="friend-row static" key={request.relId}>
                <Avatar profile={request.profile} />
                <div><b>{request.profile.display_name}</b><small>@{request.profile.username}</small></div>
                <div className="request-actions">
                  <button
                    type="button" className="tiny solid" aria-label="接受"
                    disabled={busyIds.has(request.relId)}
                    onClick={() => onRespond(request.relId, 'accepted')}
                  ><Check size={15} /></button>
                  <button
                    type="button" className="tiny ghost" aria-label="拒绝"
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
          <div className="eyebrow"><MessageCircle size={12} /> 未读消息</div>
          <div className="friend-list">
            {unreadPreviews.map(({ friend, count, last }) => (
              <button className="friend-row" key={friend.id} type="button" onClick={() => onOpenChat(friend.id)}>
                <Avatar profile={friend} showStatus />
                <div><b>{friend.display_name}</b><small>{last?.body || '有新消息'}</small></div>
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
          <div className="eyebrow"><Heart size={12} /> 收到的表情</div>
          <div className="friend-list">
            {reactions.slice(0, 8).map((reaction) => (
              <div className="friend-row static" key={reaction.id}>
                <span className="avatar reaction-avatar">{reaction.emoji}</span>
                <div>
                  <b>{nameOf(reaction.sender_id)}</b>
                  <small>给你发了 {reaction.emoji}</small>
                </div>
                <span className="friend-meta"><small>{timeAgo(reaction.created_at)}</small></span>
              </div>
            ))}
          </div>
        </>
      )}

      {placeEvents.length > 0 && (
        <>
          <div className="eyebrow"><MapPin size={12} /> 好友动态</div>
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
                  <small>{event.kind === 'arrive' ? '到了' : '离开了'} {event.label || '某个地方'}</small>
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
