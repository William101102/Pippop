import { supabase } from '../lib/supabase';
import type { Zone } from '../types';

const MISSING_TABLE = '42P01';

export const ZONE_EMOJI = ['🏠', '🏢', '🏋️', '🎓', '☕️', '🍜', '🏥', '📍'];

/** My own zones plus my friends' — RLS already limits the friend half to
 *  accepted-friendship rows, so nothing else needs filtering client side. */
export async function loadVisibleZones(): Promise<Zone[]> {
  const { data, error } = await supabase
    .from('zones')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) {
    if (error.code === MISSING_TABLE) return [];
    throw error;
  }
  return (data || []) as Zone[];
}

export async function createZone(
  ownerId: string,
  label: string,
  emoji: string,
  lat: number,
  lng: number,
  radiusM = 120,
) {
  const { data, error } = await supabase
    .from('zones')
    .insert({ owner_id: ownerId, label: label.trim(), emoji, lat, lng, radius_m: radiusM })
    .select('*')
    .single();
  if (error) {
    if (error.code === MISSING_TABLE) throw new Error('地标功能还没上线：请先运行 backend/supabase/setup.sql');
    throw error;
  }
  return data as Zone;
}

export async function deleteZone(id: string) {
  const { error } = await supabase.from('zones').delete().eq('id', id);
  if (error) throw error;
}
