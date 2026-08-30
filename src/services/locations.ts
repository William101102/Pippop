import { supabase } from '../lib/supabase';
import type { LiveLocation } from '../types';

export async function getMyLastLocation(userId: string) {
  const { data, error } = await supabase.from('locations').select('lat,lng,updated_at,user_id').eq('user_id', userId).maybeSingle();
  if (error) throw error;
  return data as LiveLocation | null;
}

export async function upsertMyLocation(location: Omit<LiveLocation, 'updated_at'> & { updated_at?: string }) {
  const row = { ...location, updated_at: location.updated_at || new Date().toISOString() };
  const { error } = await supabase.from('locations').upsert(row, { onConflict: 'user_id' });
  if (error) throw error;
}
