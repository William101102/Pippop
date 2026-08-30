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
      setMessage('ID 只能用小写字母、数字、下划线，3-20 位');
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
        <h2>还差一步</h2>
        <p className="muted">给自己起个 ID 和昵称</p>
        <label>你的 ID<input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="例如 xiaoming_01" /></label>
        <label>昵称<input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="好友会看到的名字" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? '请稍候…' : '进入 Pinpop'}</button>
      </section>
    </main>
  );
}
