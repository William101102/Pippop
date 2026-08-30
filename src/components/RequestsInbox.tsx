import { Check, X } from 'lucide-react';
import { Avatar } from './Avatar';
import type { FriendRequest } from '../types';

interface Props {
  requests: FriendRequest[];
  busyIds: Set<string>;
  onRespond: (relId: string, status: 'accepted' | 'declined') => void;
}

export function RequestsInbox({ requests, busyIds, onRespond }: Props) {
  if (!requests.length) return null;

  return (
    <div className="requests-inbox">
      <div className="eyebrow">好友请求 · {requests.length}</div>
      {requests.map((request) => (
        <div className="friend-row static" key={request.relId}>
          <Avatar profile={request.profile} />
          <div>
            <b>{request.profile.display_name}</b>
            <small>@{request.profile.username} 想加你为好友</small>
          </div>
          <div className="request-actions">
            <button
              type="button"
              className="tiny solid"
              disabled={busyIds.has(request.relId)}
              onClick={() => onRespond(request.relId, 'accepted')}
              aria-label="接受"
            ><Check size={15} /></button>
            <button
              type="button"
              className="tiny ghost"
              disabled={busyIds.has(request.relId)}
              onClick={() => onRespond(request.relId, 'declined')}
              aria-label="拒绝"
            ><X size={15} /></button>
          </div>
        </div>
      ))}
    </div>
  );
}
