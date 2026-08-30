import { Check, MessageCircle, UserPlus, X } from 'lucide-react';
import { Avatar } from './Avatar';
import { timeAgo } from '../lib/format';
import type { Friend, FriendRequest, Message } from '../types';

export interface UnreadPreview {
  friend: Friend;
  count: number;
  last?: Message;
}

interface Props {
  requests: FriendRequest[];
  unreadPreviews: UnreadPreview[];
  busyIds: Set<string>;
  onRespond: (relId: string, status: 'accepted' | 'declined') => void;
  onOpenChat: (friendId: string) => void;
}

export function NotificationsPanel({ requests, unreadPreviews, busyIds, onRespond, onOpenChat }: Props) {
  const empty = requests.length === 0 && unreadPreviews.length === 0;

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
    </div>
  );
}
