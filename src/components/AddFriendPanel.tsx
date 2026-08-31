import { useEffect, useState } from 'react';
import { Search, X } from 'lucide-react';
import { inviteText, shareText } from '../lib/geo';
import { initials } from '../lib/format';
import type { Profile } from '../types';

interface Props {
  me: Profile;
  results: Profile[];
  sentIds: Set<string>;
  friendIds: Set<string>;
  onClose: () => void;
  onSearch: (q: string) => void;
  onSendRequest: (id: string) => Promise<void>;
  onNotify: (text: string) => void;
  initialQuery?: string;
  inviteToken?: string | null;
}

export function AddFriendPanel({
  me, results, sentIds, friendIds, onClose, onSearch, onSendRequest, onNotify, initialQuery = '', inviteToken,
}: Props) {
  const [query, setQuery] = useState(initialQuery);

  useEffect(() => {
    const t = window.setTimeout(() => onSearch(query), 250);
    return () => window.clearTimeout(t);
  }, [query, onSearch]);

  useEffect(() => {
    if (initialQuery) onSearch(initialQuery);
  }, [initialQuery, onSearch]);

  async function shareSelf() {
    const text = inviteText(me.username, me.display_name, inviteToken);
    const result = await shareText('Pinpop friend invite', text, text.split('\n').pop() || '');
    onNotify(result === 'shared' ? 'Your invite was shared' : 'Invite link copied — send it to a friend! One tap and they\'re added');
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">Add friend</div><h2>Search by ID or name</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>
      <button type="button" className="my-id-card" onClick={shareSelf}>
        <div><div className="eyebrow">Your ID</div><strong>@{me.username}</strong></div>
        <span>Share with friends →</span>
      </button>
      <div className="search"><Search size={18} /><input placeholder="Enter a friend's ID or name" value={query} onChange={(e) => setQuery(e.target.value)} /></div>
      <div className="friend-list">
        {results.map((p) => {
          const already = friendIds.has(p.id);
          const sent = sentIds.has(p.id);
          return (
            <div className="friend-row static" key={p.id}>
              <span className="avatar" style={{ background: p.avatar_color }}>{initials(p.display_name)}</span>
              <div><b>{p.display_name}</b><small>@{p.username}</small></div>
              {already ? <span className="tag">Friends</span> : sent ? <span className="tag">Sent</span> : (
                <button type="button" className="tiny solid" onClick={() => onSendRequest(p.id).catch((e) => onNotify(String(e)))}>＋ Add</button>
              )}
            </div>
          );
        })}
        {query && !results.length && <div className="empty-hint">No results for "{query}"</div>}
      </div>
    </aside>
  );
}
