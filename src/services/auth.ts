import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { colorFor } from '../lib/colors';
import type { Profile } from '../types';

export async function signInWithPassword(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message === 'Invalid login credentials' ? '邮箱或密码不对，没有账号请先注册' : error.message };

  const { data: prof } = await supabase.from('profiles').select('id').eq('id', data.user!.id).maybeSingle();
  if (!prof) {
    return { session: data.session, needsProfile: true };
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
  if (taken) return { error: '这个 ID 已经被占用了，换一个试试' };

  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error) return { error: error.message };
  if (!data.session) return { error: '注册成功！请去邮箱点确认链接后再登录。', needsEmailConfirm: true, email };

  const color = colorFor(username);
  const { error: profErr } = await supabase.from('profiles').insert({
    id: data.user!.id,
    username,
    display_name: displayName,
    avatar_color: color.ring,
  });
  if (profErr) {
    await supabase.auth.signOut();
    return { error: profErr.code === '23505' ? '这个 ID 已经被占用了，换一个试试' : profErr.message };
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
