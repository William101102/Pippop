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
      setMessage('Supabase isn\'t configured yet. You can try preview mode instead.');
      return;
    }
    setBusy(true);
    setMessage('');
    if (signup) {
      if (!USERNAME_RE.test(username.trim().toLowerCase())) {
        setMessage('ID can only use lowercase letters, numbers, underscores, 3-20 characters');
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
        <h1>Your friends,<br />right on the map.</h1>
        <p>No need to ask "where are you". Open the map and see what everyone's up to.</p>
        <div className="orbit orbit-one" /><div className="orbit orbit-two" />
      </section>
      <section className="auth-card">
        <div className="eyebrow">WELCOME TO PINPOP</div>
        <h2>{signup ? 'Create your world' : 'Good to see you again'}</h2>
        <p className="muted">{signup ? 'Sign up, add friends, and light up the map together.' : 'Log in to see where your friends are.'}</p>
        <label>Email<input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="you@example.com" /></label>
        <label>Password<input value={password} onChange={(e) => setPassword(e.target.value)} type="password" placeholder="At least 6 characters" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        {signup && <>
          <label>Your ID<input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="e.g. alex_01" /></label>
          <label>Display name<input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="What friends will see" onKeyDown={(e) => e.key === 'Enter' && submit()} /></label>
        </>}
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? 'Please wait…' : signup ? 'Sign up' : 'Log in'}</button>
        <button className="text-button" type="button" onClick={() => { setSignup(!signup); setMessage(''); }}>
          {signup ? 'Already have an account? Log in' : 'First time here? Create an account'}
        </button>
        <div className="rule"><span>or</span></div>
        <button className="preview-button" type="button" onClick={onPreview}><Sparkles size={17} /> See what's new first</button>
      </section>
    </main>
  );
}
