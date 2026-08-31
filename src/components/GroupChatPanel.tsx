import { useEffect, useRef, useState } from 'react';
import { Send, X } from 'lucide-react';
import { Avatar } from './Avatar';
import type { ChatGroup, Message } from '../types';

interface Props {
  group: ChatGroup;
  messages: Message[];
  meId: string;
  onClose: () => void;
  onSend: (text: string) => Promise<{ error?: string }>;
}

export function GroupChatPanel({ group, messages, meId, onClose, onSend }: Props) {
  const [draft, setDraft] = useState('');
  const endRef = useRef<HTMLDivElement>(null);
  const memberById = new Map(group.members.map((m) => [m.id, m]));

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
        <div className="group-avatars">
          {group.members.slice(0, 3).map((m) => <Avatar key={m.id} profile={m} className="group-avatar-stack" />)}
        </div>
        <div><b>{group.name}</b><small>{group.members.length} members</small></div>
      </div>
      <div className="chat-thread">
        {messages.map((m) => {
          const mine = m.sender_id === meId;
          const author = memberById.get(m.sender_id);
          return (
            <div key={m.id} className={`chat-bubble-row ${mine ? 'mine' : 'theirs'}`}>
              {!mine && author && <Avatar profile={author} className="chat-bubble-avatar" />}
              <div>
                {!mine && author && <small className="chat-bubble-author">{author.display_name}</small>}
                <div className={`chat-bubble ${mine ? 'mine' : 'theirs'}`}>{m.body}</div>
              </div>
            </div>
          );
        })}
        <div ref={endRef} />
      </div>
      <div className="chat-input">
        <input value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Send a message…" onKeyDown={(e) => e.key === 'Enter' && submit()} />
        <button type="button" onClick={submit}><Send size={18} /></button>
      </div>
    </aside>
  );
}
