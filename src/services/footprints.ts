import { supabase } from '../lib/supabase';
import { reverseGeocode } from './checkins';
import { haversineKm } from '../lib/geo';
import type { FrequentPlace, HeatCell } from '../types';

/** Stays closer than this are the same real-world place. */
const MERGE_RADIUS_M = 50;
/** Nominatim allows ~1 request/second — geocode only the top places. */
const GEOCODE_LIMIT = 5;
const GEOCODE_DELAY_MS = 1100;

/** Lazily filled, persisted so a place keeps its name across sessions. */
const labelCache = (() => {
  try { return new Map<string, string>(Object.entries(JSON.parse(localStorage.getItem('pinpop-place-labels') || '{}'))); }
  catch { return new Map<string, string>(); }
})();

function saveLabelCache() {
  try {
    localStorage.setItem('pinpop-place-labels', JSON.stringify(Object.fromEntries(labelCache)));
  } catch { /* private mode etc */ }
}

function cacheKey(lat: number, lng: number) {
  return `${lat.toFixed(3)},${lng.toFixed(3)}`;
}

/** Merge stays that are within MERGE_RADIUS_M of each other into one place,
 *  summing the dwell time and keeping the most-visited count. Greedy over the
 *  ranked list: each entry joins the first already-kept place near it. */
function mergeNearbyPlaces(places: FrequentPlace[]): FrequentPlace[] {
  const merged: FrequentPlace[] = [];
  for (const place of places) {
    const near = merged.find(
      (m) => haversineKm(m.lat, m.lng, place.lat, place.lng) * 1000 <= MERGE_RADIUS_M,
    );
    if (!near) {
      merged.push({ ...place });
      continue;
    }
    // Weighted average keeps the pin near where the time was actually spent.
    const total = near.minutes + place.minutes || 1;
    near.lat = (near.lat * near.minutes + place.lat * place.minutes) / total;
    near.lng = (near.lng * near.minutes + place.lng * place.minutes) / total;
    near.minutes = near.minutes + place.minutes;
    near.visits = Math.max(near.visits, place.visits);
    if (place.last_seen > near.last_seen) near.last_seen = place.last_seen;
    near.label = near.label || place.label;
  }
  return merged;
}

/** Fill in human names (“XXXX High School”, “XX Apartment”) for the top
 *  places. Already-cached names are free; the rest are geocoded slowly, one
 *  per second, so we never trip the rate limit. Uncached lookups beyond the
 *  limit simply stay unnamed instead of making the panel wait. */
async function namePlaces(places: FrequentPlace[]): Promise<FrequentPlace[]> {
  const targets = places
    .filter((p) => !p.label)
    .slice(0, GEOCODE_LIMIT);
  const uncached = targets.filter((p) => !labelCache.has(cacheKey(p.lat, p.lng)));
  for (const [index, place] of uncached.entries()) {
    if (index > 0) await new Promise((r) => setTimeout(r, GEOCODE_DELAY_MS));
    const result = await reverseGeocode(place.lat, place.lng);
    const name = result?.name;
    if (name) {
      labelCache.set(cacheKey(place.lat, place.lng), name);
      place.label = name;
    }
  }
  if (uncached.length) saveLabelCache();
  for (const place of targets) {
    if (!place.label) place.label = labelCache.get(cacheKey(place.lat, place.lng));
  }
  return places;
}

export async function loadFrequentPlaces(days = 30): Promise<FrequentPlace[]> {
  const { data, error } = await supabase.rpc('my_frequent_places', { p_days: days });
  if (error) throw explain(error.code) ?? error;
  const merged = mergeNearbyPlaces((data || []) as FrequentPlace[]);
  return namePlaces(merged);
}

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
