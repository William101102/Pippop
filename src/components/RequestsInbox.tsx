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
      <div className="eyebrow">Friend requests · {requests.length}</div>
      {requests.map((request) => (
        <div className="friend-row static" key={request.relId}>
          <Avatar profile={request.profile} />
          <div>
            <b>{request.profile.display_name}</b>
            <small>@{request.profile.username} wants to be your friend</small>
          </div>
          <div className="request-actions">
            <button
              type="button"
              className="tiny solid"
              disabled={busyIds.has(request.relId)}
              onClick={() => onRespond(request.relId, 'accepted')}
              aria-label="Accept"
            ><Check size={15} /></button>
            <button
              type="button"
              className="tiny ghost"
              disabled={busyIds.has(request.relId)}
              onClick={() => onRespond(request.relId, 'declined')}
              aria-label="Decline"
            ><X size={15} /></button>
          </div>
        </div>
      ))}
    </div>
  );
}
