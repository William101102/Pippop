import { useState } from 'react';
import { Loader2, X } from 'lucide-react';
import { Avatar } from './Avatar';
import type { Friend } from '../types';

interface Props {
  friends: Friend[];
  onClose: () => void;
  onSubmit: (input: { name: string; memberIds: string[] }) => Promise<{ error?: string }>;
}

export function NewGroupSheet({ friends, onClose, onSubmit }: Props) {
  const [name, setName] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  async function submit() {
    if (!name.trim()) { setMessage('给群聊起个名字吧'); return; }
    if (selected.size < 2) { setMessage('至少选 2 位朋友才能建群'); return; }
    setBusy(true);
    setMessage('');
    const result = await onSubmit({ name, memberIds: [...selected] });
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">一起聊</div><h2>新建群聊</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <label className="checkin-field">
          群聊名字
          <input value={name} maxLength={40} placeholder="例如：周末去哪儿" onChange={(e) => setName(e.target.value)} />
        </label>

        <div className="eyebrow">选朋友（至少 2 位）</div>
        {friends.length === 0 ? (
          <p className="muted empty-hint">先加几个朋友才能建群。</p>
        ) : (
          <div className="friend-list">
            {friends.map((f) => (
              <button
                type="button"
                key={f.id}
                className={`friend-row group-pick-row ${selected.has(f.id) ? 'selected' : ''}`}
                onClick={() => toggle(f.id)}
              >
                <Avatar profile={f} />
                <div><b>{f.display_name}</b><small>@{f.username}</small></div>
                <i className="group-pick-check" />
              </button>
            ))}
          </div>
        )}

        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" type="button" disabled={busy} onClick={submit}>
          {busy ? <Loader2 size={16} className="spin" /> : `创建群聊${selected.size ? ` (${selected.size})` : ''}`}
        </button>
      </div>
    </aside>
  );
}
