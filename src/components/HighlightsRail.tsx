import { Plus } from 'lucide-react';
import { Avatar } from './Avatar';
import type { Friend, Highlight, Profile } from '../types';

interface Props {
  me: Profile;
  friends: Friend[];
  highlights: Record<string, Highlight[]>;
  busy: boolean;
  onAddMine: () => void;
  onOpen: (userId: string) => void;
}

/** Instagram/Snap-style "stories" rail: a ring around anyone (including you)
 *  with a still-live highlight, newest first. Tapping your own ring opens the
 *  viewer if you have one, otherwise starts the composer. */
export function HighlightsRail({ me, friends, highlights, busy, onAddMine, onOpen }: Props) {
  const mine = highlights[me.id] || [];
  const others = friends
    .filter((f) => (highlights[f.id] || []).length > 0)
    .sort((a, b) => {
      const at = highlights[a.id]?.[0]?.created_at ?? '';
      const bt = highlights[b.id]?.[0]?.created_at ?? '';
      return bt.localeCompare(at);
    });

  return (
    <div className="highlights-rail" role="list">
      <button
        type="button"
        role="listitem"
        className="highlight-item mine"
        onClick={() => (mine.length ? onOpen(me.id) : onAddMine())}
      >
        <span className={`highlight-ring ${mine.length ? 'live' : 'empty'}`}>
          <Avatar profile={me} />
          <i className="highlight-add" onClick={(e) => { e.stopPropagation(); onAddMine(); }}>
            <Plus size={12} />
          </i>
        </span>
        <small>{busy ? '发布中…' : '我的动态'}</small>
      </button>

      {others.map((friend) => (
        <button
          type="button"
          role="listitem"
          key={friend.id}
          className="highlight-item"
          onClick={() => onOpen(friend.id)}
        >
          <span className="highlight-ring live">
            <Avatar profile={friend} />
          </span>
          <small>{friend.display_name}</small>
        </button>
      ))}
    </div>
  );
}
