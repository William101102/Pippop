import { supabase } from '../lib/supabase';
import { colorFor } from '../lib/colors';
import { STATUSES } from '../lib/constants';
import type { GhostMode, Profile } from '../types';

export async function fetchProfile(userId: string) {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle();
  if (error) throw error;
  return data as Profile | null;
}

export async function completeProfile(userId: string, username: string, displayName: string) {
  const color = colorFor(username);
  const { error } = await supabase.from('profiles').insert({
    id: userId,
    username,
    display_name: displayName,
    avatar_color: color.ring,
  });
  if (error) {
    if (error.code === '23505') return { error: 'That ID is already taken — try another one' };
    return { error: error.message };
  }
  return { profile: await fetchProfile(userId) };
}

export async function isUsernameTaken(username: string) {
  const { data } = await supabase.from('profiles').select('id').eq('username', username).maybeSingle();
  return Boolean(data);
}

export async function updateStatus(userId: string, emoji: string, text: string) {
  const { error } = await supabase.from('profiles').update({ status_emoji: emoji, status_text: text }).eq('id', userId);
  if (error) throw error;
}

export function nextStatus(currentEmoji: string) {
  const idx = STATUSES.findIndex((s) => s.emoji === currentEmoji);
  return STATUSES[(idx + 1 + STATUSES.length) % STATUSES.length];
}

/**
 * Make a raw search box entry safe for a PostgREST `.or()` ilike filter:
 * escape the LIKE wildcards (`%` `_` `\`) so they match literally, and drop the
 * characters that would otherwise break out of the or-string syntax
 * (`,` separates conditions, `()` group them, `.` splits column.op.value).
 */
function sanitizeSearchTerm(raw: string) {
  return raw
    .trim()
    .replace(/[\\%_]/g, (m) => `\\${m}`)
    .replace(/[,().:*]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export async function searchProfiles(excludeId: string, query: string, limit = 20) {
  let q = supabase.from('profiles').select('*').neq('id', excludeId).limit(limit);
  const term = sanitizeSearchTerm(query);
  if (term) q = q.or(`username.ilike.%${term}%,display_name.ilike.%${term}%`);
  const { data, error } = await q;
  if (error) throw error;
  return (data || []) as Profile[];
}

export async function setGhostMode(ownerId: string, mode: GhostMode, frozen?: { lat: number; lng: number }) {
  const row = {
    owner_id: ownerId,
    viewer_id: ownerId,
    mode,
    frozen_lat: mode === 'frozen' ? frozen?.lat ?? null : null,
    frozen_lng: mode === 'frozen' ? frozen?.lng ?? null : null,
    updated_at: new Date().toISOString(),
  };

  const { error } = await supabase.from('location_privacy').upsert(row, {
    onConflict: 'owner_id,viewer_id',
  });
  if (error) throw error;

  // Legacy rows from the old null-viewer default are no longer used.
  await supabase.from('location_privacy').delete().eq('owner_id', ownerId).is('viewer_id', null);
}

export async function getGhostMode(ownerId: string): Promise<GhostMode> {
  const { data, error } = await supabase
    .from('location_privacy')
    .select('mode')
    .eq('owner_id', ownerId)
    .eq('viewer_id', ownerId)
    .maybeSingle();
  if (error && error.code !== '42P01') throw error;
  if (data?.mode) return data.mode as GhostMode;

  const legacy = await supabase
    .from('location_privacy')
    .select('mode')
    .eq('owner_id', ownerId)
    .is('viewer_id', null)
    .maybeSingle();
  if (legacy.error && legacy.error.code !== '42P01') throw legacy.error;
  return (legacy.data?.mode as GhostMode) || 'precise';
}

/** Per-friend override; `null` clears it so the account default applies again. */
export async function setFriendGhostMode(ownerId: string, viewerId: string, mode: GhostMode | null) {
  if (!mode) {
    const { error } = await supabase
      .from('location_privacy')
      .delete()
      .eq('owner_id', ownerId)
      .eq('viewer_id', viewerId);
    if (error && error.code !== '42P01') throw error;
    return;
  }

  const row = {
    owner_id: ownerId,
    viewer_id: viewerId,
    mode,
    frozen_lat: null,
    frozen_lng: null,
    updated_at: new Date().toISOString(),
  };

  const { error } = await supabase.from('location_privacy').upsert(row, {
    onConflict: 'owner_id,viewer_id',
  });
  if (error && error.code !== '42P01') throw error;
}

export async function getFriendGhostModes(ownerId: string): Promise<Record<string, GhostMode>> {
  const { data, error } = await supabase
    .from('location_privacy')
    .select('viewer_id,mode')
    .eq('owner_id', ownerId)
    .not('viewer_id', 'is', null);
  if (error) {
    if (error.code === '42P01') return {};
    throw error;
  }
  const modes: Record<string, GhostMode> = {};
  for (const row of (data || []) as { viewer_id: string; mode: GhostMode }[]) {
    modes[row.viewer_id] = row.mode;
  }
  return modes;
}

export async function updateBattery(userId: string, level: number, charging: boolean) {
  const { error } = await supabase
    .from('profiles')
    .update({ battery_level: Math.round(level * 100), is_charging: charging, last_active_at: new Date().toISOString() })
    .eq('id', userId);
  if (error) throw error;
}

/**
 * Irreversible. The server cascades every row from auth.users and drops the
 * stored avatars, so there is nothing left to clean up client side beyond
 * ending the session.
 */
export async function deleteMyAccount() {
  const { error } = await supabase.rpc('delete_my_account');
  if (error) {
    if (error.code === '42883') {
      throw new Error('The account-deletion feature is not installed on the server yet — run setup.sql first');
    }
    throw error;
  }
  await supabase.auth.signOut();
}
