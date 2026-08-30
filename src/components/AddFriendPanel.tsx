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
}

export function AddFriendPanel({ me, results, sentIds, friendIds, onClose, onSearch, onSendRequest, onNotify, initialQuery = '' }: Props) {
  const [query, setQuery] = useState(initialQuery);

  useEffect(() => {
    const t = window.setTimeout(() => onSearch(query), 250);
    return () => window.clearTimeout(t);
  }, [query, onSearch]);

  useEffect(() => {
    if (initialQuery) onSearch(initialQuery);
  }, [initialQuery, onSearch]);

  async function shareSelf() {
    const text = inviteText(me.username, me.display_name);
    const result = await shareText('Pinpop 好友邀请', text, text.split('\n').pop() || '');
    onNotify(result === 'shared' ? '已分享你的邀请' : '邀请链接已复制，发给朋友吧！');
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">添加好友</div><h2>搜索 ID 或名字</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>
      <button type="button" className="my-id-card" onClick={shareSelf}>
        <div><div className="eyebrow">你的 ID</div><strong>@{me.username}</strong></div>
        <span>分享给朋友 →</span>
      </button>
      <div className="search"><Search size={18} /><input placeholder="输入好友 ID 或名字" value={query} onChange={(e) => setQuery(e.target.value)} /></div>
      <div className="friend-list">
        {results.map((p) => {
          const already = friendIds.has(p.id);
          const sent = sentIds.has(p.id);
          return (
            <div className="friend-row static" key={p.id}>
              <span className="avatar" style={{ background: p.avatar_color }}>{initials(p.display_name)}</span>
              <div><b>{p.display_name}</b><small>@{p.username}</small></div>
              {already ? <span className="tag">已是好友</span> : sent ? <span className="tag">已发送</span> : (
                <button type="button" className="tiny solid" onClick={() => onSendRequest(p.id).catch((e) => onNotify(String(e)))}>＋ 添加</button>
              )}
            </div>
          );
        })}
        {query && !results.length && <div className="empty-hint">没找到「{query}」</div>}
      </div>
    </aside>
  );
}
