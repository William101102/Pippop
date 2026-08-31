import { useState } from 'react';
import { STATUSES } from '../lib/constants';
import type { Profile } from '../types';

const EMOJI_CHOICES = ['🏠', '💼', '🍔', '🎧', '🚶', '🏃', '☕️', '🎮', '📚', '😴', '🎉', '🛫'];

interface Props {
  profile: Profile;
  onSave: (emoji: string, text: string) => Promise<{ error?: string }>;
}

export function StatusEditor({ profile, onSave }: Props) {
  const [emoji, setEmoji] = useState(profile.status_emoji || '🏠');
  const [text, setText] = useState(profile.status_text || '');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  const dirty = emoji !== profile.status_emoji || text !== profile.status_text;

  async function save() {
    if (!text.trim()) { setMessage('Write a line about what you\'re up to'); return; }
    setBusy(true);
    setMessage('');
    const result = await onSave(emoji, text.trim());
    setBusy(false);
    setMessage(result.error || '');
  }

  return (
    <div className="status-editor">
      <div className="eyebrow">Status right now</div>
      <div className="emoji-row">
        {EMOJI_CHOICES.map((choice) => (
          <button
            key={choice}
            type="button"
            className={emoji === choice ? 'selected' : ''}
            onClick={() => setEmoji(choice)}
          >{choice}</button>
        ))}
      </div>
      <div className="status-input">
        <span>{emoji}</span>
        <input
          value={text}
          maxLength={40}
          placeholder="What are you up to?"
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') save(); }}
        />
      </div>
      <div className="status-presets">
        {STATUSES.map((preset) => (
          <button
            key={preset.text}
            type="button"
            className="tiny ghost"
            onClick={() => { setEmoji(preset.emoji); setText(preset.text); }}
          >{preset.emoji} {preset.text}</button>
        ))}
      </div>
      {message && <div className="form-message">{message}</div>}
      <button className="primary compact" type="button" disabled={busy || !dirty} onClick={save}>
        {busy ? 'Saving…' : dirty ? 'Save status' : 'Up to date'}
      </button>
    </div>
  );
}
