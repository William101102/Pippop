import { supabase } from '../lib/supabase';
import type { FrequentPlace, HeatCell } from '../types';

/** Raised when the server functions are not installed yet. */
const MISSING_FUNCTION = '42883';

function explain(code: string | undefined) {
  if (code === MISSING_FUNCTION) {
    return new Error('The footprints feature is not installed on the server yet — run setup.sql first');
  }
  return null;
}

export async function loadHeatmap(days = 30): Promise<HeatCell[]> {
  const { data, error } = await supabase.rpc('my_heatmap', { p_days: days });
  if (error) throw explain(error.code) ?? error;
  return (data || []) as HeatCell[];
}

export async function loadFrequentPlaces(days = 30): Promise<FrequentPlace[]> {
  const { data, error } = await supabase.rpc('my_frequent_places', { p_days: days });
  if (error) throw explain(error.code) ?? error;
  return (data || []) as FrequentPlace[];
}

/**
 * The most recent fixes, oldest first, so the map can draw them as a path.
 * Capped because a long trail is unreadable as well as slow.
 */
export async function loadRecentTrail(hours = 12, limit = 300) {
  const since = new Date(Date.now() - hours * 3600_000).toISOString();
  const { data, error } = await supabase
    .from('location_history')
    .select('lat,lng,recorded_at')
    .gte('recorded_at', since)
    .order('recorded_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  const rows = (data || []) as { lat: number; lng: number; recorded_at: string }[];
  return rows.reverse();
}
