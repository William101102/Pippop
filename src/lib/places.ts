import { haversineKm } from "./geo";

/**
 * Significant-place detection, pure functions so they are unit-testable.
 *
 * Overnight spot: staying >= 5 h within the local window 00:01–11:00.
 * Home: an overnight spot with >= 10 nights, ranked in the top 2 by nights.
 * Work: outside the overnight window, the place with the most time stayed.
 *
 * All "stays" are derived from observed location fixes; when the app is
 * closed no points exist, so a stay is only credited for the observed span.
 */

/** Cluster cell size in degrees (~55 m latitude). */
const CELL_DEG = 0.0005;
/** Points within this distance (m) of a cluster are the same stay. */
const CLUSTER_RADIUS_M = 80;
/** Minimum minutes inside the overnight window to count as an overnight stay. */
export const OVERNIGHT_MIN_MINUTES = 5 * 60;
/** Distinct nights required before an overnight spot can become home. */
export const HOME_MIN_NIGHTS = 10;
export const HOME_MAX_COUNT = 2;
/** Overnight window in local hours: 00:01 – 11:00. */
export const OVERNIGHT_START_MIN = 1; // 00:01
export const OVERNIGHT_END_MIN = 11 * 60; // 11:00

export interface VisitPoint {
  lat: number;
  lng: number;
  recorded_at: string; // ISO
}

export type PlaceKind = "overnight" | "home" | "work";

export interface SignificantPlace {
  id?: string;
  kind: PlaceKind;
  lat: number;
  lng: number;
  label: string;
  /** overnight: nights count; work: total minutes. */
  score: number;
  first_seen_at?: string;
  last_seen_at?: string;
}

function minutesIntoLocalDay(iso: string) {
  const d = new Date(iso);
  return d.getHours() * 60 + d.getMinutes();
}

function inOvernightWindow(iso: string) {
  const m = minutesIntoLocalDay(iso);
  return m >= OVERNIGHT_START_MIN && m <= OVERNIGHT_END_MIN;
}

function localDayKey(iso: string) {
  const d = new Date(iso);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

/** True when the segment between two consecutive fixes crosses out of (or into) the overnight window. */
function windowChanges(aIso: string, bIso: string) {
  return inOvernightWindow(aIso) !== inOvernightWindow(bIso);
}

export interface Stay {
  lat: number;
  lng: number;
  /** Minutes from first to last fix in the stay. */
  minutes: number;
  startIso: string;
  endIso: string;
  /** True when the stay falls inside the overnight window. */
  overnight: boolean;
  /** Local days overlapping the stay (for distinct-night counting). */
  days: string[];
}

/**
 * Split an ordered list of fixes into stays. Consecutive fixes within
 * CLUSTER_RADIUS_M belong to the same stay; a window boundary or a jump
 * larger than the radius ends the stay.
 */
export function extractStays(points: VisitPoint[]): Stay[] {
  const sorted = [...points].sort(
    (a, b) =>
      new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime(),
  );
  const stays: Stay[] = [];
  let cur: { points: VisitPoint[] } | null = null;

  const flush = () => {
    if (!cur || cur.points.length === 0) {
      cur = null;
      return;
    }
    const ps = cur.points;
    const startIso = ps[0].recorded_at;
    const endIso = ps[ps.length - 1].recorded_at;
    const days = Array.from(new Set(ps.map((p) => localDayKey(p.recorded_at))));
    stays.push({
      lat: avg(ps.map((p) => p.lat)),
      lng: avg(ps.map((p) => p.lng)),
      minutes:
        (new Date(endIso).getTime() - new Date(startIso).getTime()) / 60000,
      startIso,
      endIso,
      overnight: inOvernightWindow(startIso),
      days,
    });
    cur = null;
  };

  for (const p of sorted) {
    if (
      cur &&
      (haversineKm(lastLat(cur), lastLng(cur), p.lat, p.lng) * 1000 >
        CLUSTER_RADIUS_M ||
        windowChanges(lastIso(cur), p.recorded_at))
    ) {
      flush();
    }
    if (!cur) cur = { points: [] };
    cur.points.push(p);
  }
  flush();
  return stays;
}

// The helpers below keep `cur` typed as a non-null box inside the loop above.
function lastLat(box: { points: VisitPoint[] }) {
  return box.points[box.points.length - 1].lat;
}
function lastLng(box: { points: VisitPoint[] }) {
  return box.points[box.points.length - 1].lng;
}
function lastIso(box: { points: VisitPoint[] }) {
  return box.points[box.points.length - 1].recorded_at;
}
function avg(xs: number[]) {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

/** Merge stays that share a grid cell, summing minutes / unioning days. */
function mergeStays(stays: Stay[]) {
  const map = new Map<string, Stay & { daySet: Set<string> }>();
  for (const s of stays) {
    const key = `${Math.round(s.lat / CELL_DEG)}:${Math.round(s.lng / CELL_DEG)}`;
    const prev = map.get(key);
    if (prev) {
      prev.minutes += s.minutes;
      s.days.forEach((d) => prev.daySet.add(d));
    } else {
      map.set(key, { ...s, daySet: new Set(s.days) });
    }
  }
  return Array.from(map.entries()).map(([key, s]) => ({
    key,
    lat: s.lat,
    lng: s.lng,
    minutes: s.minutes,
    overnight: s.overnight,
    days: Array.from(s.daySet),
  }));
}

export interface DetectedPlaces {
  overnightSpots: SignificantPlace[];
  home: SignificantPlace[];
  work: SignificantPlace | null;
}

export function detectSignificantPlaces(points: VisitPoint[]): DetectedPlaces {
  const merged = mergeStays(extractStays(points));

  // ---- Overnight spots -------------------------------------------------
  const overnight = merged
    .filter((s) => s.overnight)
    .map((s) => ({
      kind: "overnight" as const,
      lat: s.lat,
      lng: s.lng,
      label: "过夜地点",
      score: s.days.length,
    }))
    .filter((p) => p.score > 0)
    .sort((a, b) => b.score - a.score);

  // ---- Home: >= HOME_MIN_NIGHTS nights, top HOME_MAX_COUNT ------------
  const home = overnight
    .filter((p) => p.score >= HOME_MIN_NIGHTS)
    .slice(0, HOME_MAX_COUNT)
    .map((p) => ({ ...p, label: "Home" }));

  // ---- Work: most time outside the overnight window -------------------
  const workStay = merged
    .filter((s) => !s.overnight && s.minutes > 0)
    .sort((a, b) => b.minutes - a.minutes)[0];
  const work: SignificantPlace | null = workStay
    ? {
        kind: "work",
        lat: workStay.lat,
        lng: workStay.lng,
        label: "Work",
        score: Math.round(workStay.minutes),
      }
    : null;

  return { overnightSpots: overnight, home, work };
}

/** Places to persist: all overnight spots plus home/work upgrades. */
export function placesToPersist(detected: DetectedPlaces): SignificantPlace[] {
  const homeKeys = new Set(detected.home.map((p) => `${p.lat},${p.lng}`));
  const overnight = detected.overnightSpots.filter(
    (p) => !homeKeys.has(`${p.lat},${p.lng}`),
  );
  const out: SignificantPlace[] = [...overnight, ...detected.home];
  if (detected.work) out.push(detected.work);
  return out;
}
