import { useState } from 'react';
import { Sparkles } from 'lucide-react';
import { isConfigured } from '../lib/supabase';
import { USERNAME_RE } from '../lib/constants';

interface Props {
  onLogin: (email: string, password: string) => Promise<{ error?: string; needsSignup?: boolean; email?: string }>;
  onRegister: (input: { email: string; password: string; username: string; displayName: string }) => Promise<{ error?: string; needsEmailConfirm?: boolean; email?: string }>;
  onPreview: () => void;
  initialSignup?: boolean;
  initialEmail?: string;
}

export function AuthScreen({ onLogin, onRegister, onPreview, initialSignup = false, initialEmail = '' }: Props) {
  const [signup, setSignup] = useState(initialSignup);
  const [email, setEmail] = useState(initialEmail);
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!isConfigured) {
      setMessage('尚未配置 Supabase。可先进入预览模式。');
      return;
    }
    setBusy(true);
    setMessage('');
    if (signup) {
      if (!USERNAME_RE.test(username.trim().toLowerCase())) {
        setMessage('ID 只能用小写字母、数字、下划线，3-20 位');
        setBusy(false);
        return;
      }
      const result = await onRegister({
        email: email.trim(),
        password,
        username: username.trim().toLowerCase(),
        displayName: displayName.trim() || username.trim().toLowerCase(),
      });
      setBusy(false);
      if (result.error) {
        setMessage(result.error);
        if (result.needsEmailConfirm) {
          setSignup(false);
          setEmail(result.email || email);
        }
      }
      return;
    }
    const result = await onLogin(email.trim(), password);
    setBusy(false);
    if (result.error) {
      setMessage(result.error);
      if (result.needsSignup) {
        setSignup(true);
        setEmail(result.email || email);
      }
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-copy">
        <div className="brand brand-large"><span>pin</span>pop<i>●</i></div>
        <h1>你的朋友，<br />就在地图上。</h1>
        <p>不用问“你在哪”。打开地图，看看大家正在做什么。</p>
        <div className="orbit orbit-one" /><div className="orbit orbit-two" />
      </section>
      <section className="auth-card">
        <div className="eyebrow">欢迎来到 PINPOP</div>
        <h2>{signup ? '创建你的世界' : '再次见到你真好'}</h2>
        <p className="muted">{signup ? '注册后添加朋友，一起点亮地图。' : '登录后继续看看朋友们在哪里。'}</p>
        <label>邮箱<input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="you@example.com" /></label>
        <label>密码<input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="至少 6 位" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        {signup && <>
          <label>你的 ID<input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="例如 xiaoming_01" /></label>
          <label>昵称<input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="好友会看到的名字" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        </>}
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? '请稍候…' : signup ? '注册' : '登录'}</button>
        <button className="text-button" type="button" onClick={() => { setSignup(!signup); setMessage(''); }}>
          {signup ? '已经有账号？登录' : '第一次来？创建账号'}
        </button>
        <div className="rule"><span>或者</span></div>
        <button className="preview-button" type="button" onClick={onPreview}><Sparkles size={17} /> 先看看新版长什么样</button>
      </section>
    </main>
  );
}
