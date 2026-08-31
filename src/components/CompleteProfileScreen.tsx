import { useState } from 'react';
import { USERNAME_RE } from '../lib/constants';

interface Props {
  onComplete: (username: string, displayName: string) => Promise<{ error?: string }>;
}

export function CompleteProfileScreen({ onComplete }: Props) {
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    const u = username.trim().toLowerCase();
    if (!USERNAME_RE.test(u)) {
      setMessage('ID can only use lowercase letters, numbers, underscores, 3-20 characters');
      return;
    }
    setBusy(true);
    const result = await onComplete(u, displayName.trim() || u);
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <main className="auth-shell">
      <section className="auth-card" style={{ maxWidth: 420 }}>
        <div className="brand brand-large"><span>pin</span>pop<i>●</i></div>
        <h2>One more step</h2>
        <p className="muted">Pick an ID and a display name</p>
        <label>Your ID<input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="e.g. alex_01" /></label>
        <label>Display name<input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="What friends will see" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? 'Please wait…' : 'Enter Pinpop'}</button>
      </section>
    </main>
  );
}
