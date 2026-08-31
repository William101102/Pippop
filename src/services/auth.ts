import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { colorFor } from '../lib/colors';
import type { Profile } from '../types';

export async function signInWithPassword(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message === 'Invalid login credentials' ? 'Wrong email or password — sign up first if you don\'t have an account' : error.message };

  const { data: prof } = await supabase.from('profiles').select('id').eq('id', data.user!.id).maybeSingle();
  if (!prof) {
    await supabase.auth.signOut();
    return { error: 'This email isn\'t registered yet — create an account under "Sign up" first', needsSignup: true, email };
  }
  return { session: data.session };
}

export async function signUp(input: {
  email: string;
  password: string;
  username: string;
  displayName: string;
}) {
  const { email, password, username, displayName } = input;
  const { data: taken } = await supabase.from('profiles').select('id').eq('username', username).maybeSingle();
  if (taken) return { error: 'That ID is already taken — try another one' };

  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error) return { error: error.message };
  if (!data.session) return { error: 'Signed up! Please check your email to confirm before logging in.', needsEmailConfirm: true, email };

  const color = colorFor(username);
  const { error: profErr } = await supabase.from('profiles').insert({
    id: data.user!.id,
    username,
    display_name: displayName,
    avatar_color: color.ring,
  });
  if (profErr) {
    await supabase.auth.signOut();
    return { error: profErr.code === '23505' ? 'That ID is already taken — try another one' : profErr.message };
  }
  return { session: data.session };
}

export async function signOut() {
  await supabase.auth.signOut();
}

export function onAuthStateChange(cb: (session: Session | null) => void) {
  return supabase.auth.onAuthStateChange((_event, session) => cb(session));
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}
