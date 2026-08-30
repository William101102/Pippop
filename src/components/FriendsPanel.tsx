import { Search } from 'lucide-react';
import { fmtDist, timeAgo } from '../lib/format';
import { haversineKm } from '../lib/geo';
import { initials } from '../lib/format';
import type { Friend, FriendRequest, LiveLocation } from '../types';

interface Props {
  friends: Friend[];
  requests: FriendRequest[];
  myLocation: LiveLocation | null;
  search: string;
  onSearch: (value: string) => void;
  onSelectFriend: (friend: Friend) => void;
  onRespond: (relId: string, status: 'accepted' | 'declined') => void;
}

export function FriendsPanel({ friends, requests, myLocation, search, onSearch, onSelectFriend, onRespond }: Props) {
  const q = search.trim().toLowerCase();
  const filtered = friends.filter((f) => `${f.display_name} ${f.username}`.toLowerCase().includes(q));

  return (
    <>
      <div className="search"><Search size={18} /><input placeholder="搜索朋友" value={search} onChange={(e) => onSearch(e.target.value)} /></div>
      {requests.length > 0 && (
        <div className="request-block">
          <div className="eyebrow">好友请求 · {requests.length}</div>
          {requests.map((r) => (
            <div className="request-row" key={r.relId}>
              <span className="avatar" style={{ background: r.profile.avatar_color }}>{initials(r.profile.display_name)}</span>
              <div><b>{r.profile.display_name}</b><small>@{r.profile.username} 想加你为好友</small></div>
              <button type="button" className="tiny ghost" onClick={() => onRespond(r.relId, 'declined')}>拒绝</button>
              <button type="button" className="tiny solid" onClick={() => onRespond(r.relId, 'accepted')}>接受</button>
            </div>
          ))}
        </div>
      )}
      <div className="friend-list">
        {filtered.map((f) => {
          const dist = f.location && myLocation ? fmtDist(haversineKm(myLocation.lat, myLocation.lng, f.location.lat, f.location.lng)) : '—';
          return (
            <button className="friend-row" type="button" key={f.id} onClick={() => onSelectFriend(f)}>
              <span className="avatar" style={{ background: f.avatar_color }}>{initials(f.display_name)}<i>{f.status_emoji}</i></span>
              <div><b>{f.display_name}</b><small>@{f.username} · {f.status_text} · {dist}</small></div>
              <div className="friend-meta"><span>{timeAgo(f.location?.updated_at)}</span></div>
            </button>
          );
        })}
        {!filtered.length && <div className="empty-hint">还没有好友，点右上角 ＋ 去添加吧</div>}
      </div>
    </>
  );
}
