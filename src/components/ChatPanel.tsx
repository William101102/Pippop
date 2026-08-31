import { useEffect, useRef, useState } from 'react';
import { Send, X } from 'lucide-react';
import { initials } from '../lib/format';
import type { Friend, Message } from '../types';

interface Props {
  friend: Friend;
  messages: Message[];
  meId: string;
  onClose: () => void;
  onSend: (text: string) => Promise<{ error?: string }>;
}

export function ChatPanel({ friend, messages, meId, onClose, onSend }: Props) {
  const [draft, setDraft] = useState('');
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function submit() {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    const result = await onSend(text);
    if (result.error) setDraft(text);
  }

  return (
    <aside className="sheet sheet-full chat-panel">
      <div className="sheet-head">
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
        <span className="avatar" style={{ background: friend.avatar_color }}>{initials(friend.display_name)}</span>
        <div><b>{friend.display_name}</b><small>{friend.status_emoji} {friend.status_text}</small></div>
      </div>
      <div className="chat-thread">
        {messages.map((m) => (
          <div key={m.id} className={`chat-bubble ${m.sender_id === meId ? 'mine' : 'theirs'}`}>{m.body}</div>
        ))}
        <div ref={endRef} />
      </div>
      <div className="chat-input">
        <input value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Send a message…" onKeyDown={(e) => e.key === 'Enter' && submit()} />
        <button type="button" onClick={submit}><Send size={18} /></button>
      </div>
    </aside>
  );
}
