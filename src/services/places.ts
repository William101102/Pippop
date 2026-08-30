import { supabase } from '../lib/supabase';
import type { SignificantPlace, VisitPoint } from '../lib/places';

const CELL_DEG = 0.0005;

export async function loadLocationHistory(userId: string, sinceDays = 30): Promise<VisitPoint[]> {
  const since = new Date(Date.now() - sinceDays * 86400000).toISOString();
  const { data, error } = await supabase
    .from('location_history')
    .select('lat,lng,recorded_at')
    .eq('user_id', userId)
    .gte('recorded_at', since)
    .order('recorded_at', { ascending: true })
    .limit(5000);
  if (error) throw error;
  return (data || []) as VisitPoint[];
}

export async function appendLocationHistory(userId: string, lat: number, lng: number, recordedAt: string) {
  const { error } = await supabase.from('location_history').insert({
    user_id: userId,
    lat,
    lng,
    recorded_at: recordedAt,
    cell_lat: Math.round(lat / CELL_DEG),
    cell_lng: Math.round(lng / CELL_DEG),
  });
  if (error) throw error;
}

export async function loadSignificantPlaces(userId: string): Promise<SignificantPlace[]> {
  const { data, error } = await supabase
    .from('significant_places')
    .select('*')
    .eq('user_id', userId)
    .order('score', { ascending: false });
  if (error) throw error;
  return (data || []) as SignificantPlace[];
}

export async function upsertSignificantPlaces(userId: string, places: SignificantPlace[]) {
  if (!places.length) return;
  const rows = places.map((p) => ({
    user_id: userId,
    kind: p.kind,
    lat: p.lat,
    lng: p.lng,
    label: p.label,
    score: p.score,
    last_seen_at: new Date().toISOString(),
    cell_lat: Math.round(p.lat / CELL_DEG),
    cell_lng: Math.round(p.lng / CELL_DEG),
  }));
  const { error } = await supabase
    .from('significant_places')
    .upsert(rows, { onConflict: 'user_id,kind,cell_lat,cell_lng' });
  if (error) throw error;
}

export async function deleteSignificantPlaces(userId: string, kinds: SignificantPlace['kind'][]) {
  const { error } = await supabase.from('significant_places').delete().eq('user_id', userId).in('kind', kinds);
  if (error) throw error;
}
