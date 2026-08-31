import { supabase } from '../lib/supabase';
import { haversineKm } from '../lib/geo';
import type { CheckInPlace, NearbyPlace, PlaceCategory, Visit, VisitVisibility } from '../types';

/** Rough degrees-per-km at the equator; good enough for a bounding-box prefilter. */
const DEG_PER_KM = 1 / 111;

export async function reverseGeocode(lat: number, lng: number) {
  const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&addressdetails=1&lat=${lat}&lon=${lng}`;
  try {
    const response = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!response.ok) return null;
    const data = await response.json();
    const address = data?.address ?? {};
    const name = data?.name
      || address.amenity
      || address.shop
      || address.building
      || address.road
      || address.neighbourhood
      || address.suburb
      || null;
    return { name: name as string | null, address: (data?.display_name as string | undefined) ?? null };
  } catch {
    return null;
  }
}

export async function checkIn(
  userId: string,
  input: {
    name: string;
    category: PlaceCategory;
    lat: number;
    lng: number;
    address?: string | null;
    visibility: VisitVisibility;
    note?: string;
  },
) {
  const name = input.name.trim();
  if (!name) return { error: 'Give this place a name' };

  const { data: place, error: placeError } = await supabase
    .from('places')
    .insert({
      name,
      category: input.category,
      address: input.address ?? null,
      lat: input.lat,
      lng: input.lng,
      source: 'user',
      created_by: userId,
    })
    .select('id,name,category,address,lat,lng,created_by')
    .single();
  if (placeError) return { error: placeError.message };

  const { error: visitError } = await supabase.from('visits').insert({
    user_id: userId,
    place_id: (place as CheckInPlace).id,
    visibility: input.visibility,
    note: input.note?.trim() || null,
  });
  if (visitError) return { error: visitError.message };

  return { place: place as CheckInPlace };
}

export async function loadNearbyPlaces(lat: number, lng: number, radiusKm = 5): Promise<NearbyPlace[]> {
  const pad = radiusKm * DEG_PER_KM;
  const lngPad = pad / Math.max(Math.cos((lat * Math.PI) / 180), 0.01);
  const { data, error } = await supabase
    .from('places')
    .select('id,name,category,address,lat,lng,created_by')
    .gte('lat', lat - pad)
    .lte('lat', lat + pad)
    .gte('lng', lng - lngPad)
    .lte('lng', lng + lngPad)
    .limit(200);
  if (error) throw error;

  return ((data || []) as CheckInPlace[])
    .map((place) => ({ ...place, distanceKm: haversineKm(lat, lng, place.lat, place.lng) }))
    .filter((place) => place.distanceKm <= radiusKm)
    .sort((a, b) => a.distanceKm - b.distanceKm);
}

export async function loadMyVisits(userId: string, limit = 30): Promise<Visit[]> {
  const { data, error } = await supabase
    .from('visits')
    .select('id,user_id,place_id,arrived_at,visibility,note,place:places(id,name,category,address,lat,lng,created_by)')
    .eq('user_id', userId)
    .order('arrived_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data || []) as unknown as Visit[];
}

/** Own check-ins plus any a friend chose to share. */
export async function loadVisitFeed(limit = 30): Promise<Visit[]> {
  const { data, error } = await supabase
    .from('visits')
    .select('id,user_id,place_id,arrived_at,visibility,note,place:places(id,name,category,address,lat,lng,created_by)')
    .order('arrived_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data || []) as unknown as Visit[];
}

export async function deleteVisit(visitId: string) {
  const { error } = await supabase.from('visits').delete().eq('id', visitId);
  if (error) throw error;
}
