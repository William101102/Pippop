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

  // The chosen name has to travel with the signup, not just be written
  // afterwards: `handle_new_user` (202608300003_auth_profile_bootstrap)
  // creates the profile row the instant the auth user exists, and reads
  // these two keys. Without them it falls back to `user_xxxxxxxx`, which is
  // the name someone confirming by email would then be stuck with — the
  // client code below never runs in that flow.
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { username, display_name: displayName } },
  });
  if (error) return { error: error.message };
  if (!data.session) return { error: 'Signed up! Please check your email to confirm before logging in.', needsEmailConfirm: true, email };

  const color = colorFor(username);
  // `upsert`, not `insert`. The bootstrap trigger has already inserted a row
  // for this id, so a plain insert always failed with 23505 — on the *id*
  // primary key, not on the username — and the branch below read that as
  // "that ID is taken", signed the new user straight back out, and left them
  // unable to ever sign up. Upsert updates the row the trigger made, and
  // still works if the trigger isn't installed.
  const { error: profErr } = await supabase.from('profiles').upsert({
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
