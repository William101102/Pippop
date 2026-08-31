import { Plus } from 'lucide-react';
import { Avatar } from './Avatar';
import type { Friend, Profile } from '../types';

interface Props {
  me: Profile;
  friends: Friend[];
  unread: Record<string, number>;
  activeId: string | null;
  onSelectMe: () => void;
  onSelectFriend: (friend: Friend) => void;
  onAddFriend: () => void;
}

export function FriendRail({ me, friends, unread, activeId, onSelectMe, onSelectFriend, onAddFriend }: Props) {
  return (
    <div className="friend-rail" role="list">
      <button
        type="button"
        role="listitem"
        className={`rail-item ${activeId === me.id ? 'active' : ''}`}
        onClick={onSelectMe}
      >
        <span className="rail-avatar mine">
          <Avatar profile={me} showStatus />
        </span>
        <small>You</small>
      </button>

      {friends.map((friend) => (
        <button
          type="button"
          role="listitem"
          key={friend.id}
          className={`rail-item ${activeId === friend.id ? 'active' : ''}`}
          onClick={() => onSelectFriend(friend)}
        >
          <span className="rail-avatar">
            <Avatar profile={friend} showStatus />
            {(unread[friend.id] || 0) > 0 && <i className="rail-badge">{unread[friend.id]}</i>}
          </span>
          <small>{friend.display_name}</small>
        </button>
      ))}

      <button type="button" className="rail-item rail-add" onClick={onAddFriend}>
        <span className="rail-avatar"><Plus size={20} /></span>
        <small>Add</small>
      </button>
    </div>
  );
}
