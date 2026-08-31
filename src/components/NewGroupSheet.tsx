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
    if (!name.trim()) { setMessage('Give the group chat a name'); return; }
    if (selected.size < 2) { setMessage('Pick at least 2 friends to start a group'); return; }
    setBusy(true);
    setMessage('');
    const result = await onSubmit({ name, memberIds: [...selected] });
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">Chat together</div><h2>New group chat</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <label className="checkin-field">
          Group name
          <input value={name} maxLength={40} placeholder="e.g. Weekend plans" onChange={(e) => setName(e.target.value)} />
        </label>

        <div className="eyebrow">Pick friends (at least 2)</div>
        {friends.length === 0 ? (
          <p className="muted empty-hint">Add some friends first to start a group.</p>
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
          {busy ? <Loader2 size={16} className="spin" /> : `Create group${selected.size ? ` (${selected.size})` : ''}`}
        </button>
      </div>
    </aside>
  );
}
