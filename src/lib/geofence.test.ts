import { describe, expect, it } from 'vitest';
import { createGeofenceTracker } from './geofence';
import type { SignificantPlace } from './places';

const HOME: SignificantPlace = {
  kind: 'overnight',
  label: '家',
  lat: 37.3317,
  lng: -121.8929,
  score: 3,
};

const OFFICE: SignificantPlace = {
  kind: 'work',
  label: '公司',
  lat: 37.3917,
  lng: -121.8929,
  score: 2,
};

/** Roughly 111km per degree of latitude, so this converts metres to an offset. */
function northOf(place: SignificantPlace, metres: number) {
  return { lat: place.lat + metres / 111_000, lng: place.lng };
}

describe('geofence tracker', () => {
  it('reports arriving at the nearest place', () => {
    const tracker = createGeofenceTracker();
    const at = northOf(HOME, 30);
    const transition = tracker.update(at.lat, at.lng, [HOME, OFFICE]);
    expect(transition).toEqual({ kind: 'arrive', place: HOME });
  });

  it('does not report arriving from far away', () => {
    const tracker = createGeofenceTracker();
    const at = northOf(HOME, 900);
    expect(tracker.update(at.lat, at.lng, [HOME])).toBeNull();
  });

  it('reports arriving only once while you stay put', () => {
    const tracker = createGeofenceTracker();
    const at = northOf(HOME, 20);
    expect(tracker.update(at.lat, at.lng, [HOME])).not.toBeNull();
    expect(tracker.update(at.lat, at.lng, [HOME])).toBeNull();
    expect(tracker.update(HOME.lat, HOME.lng, [HOME])).toBeNull();
  });

  it('does not flap when a stationary fix drifts between the two radii', () => {
    const tracker = createGeofenceTracker();
    const inside = northOf(HOME, 20);
    expect(tracker.update(inside.lat, inside.lng, [HOME])).not.toBeNull();

    // Past the arrive radius but not the leave radius: still counts as at home.
    const drifted = northOf(HOME, 150);
    expect(tracker.update(drifted.lat, drifted.lng, [HOME])).toBeNull();
    expect(tracker.update(inside.lat, inside.lng, [HOME])).toBeNull();
  });

  it('reports leaving once past the leave radius', () => {
    const tracker = createGeofenceTracker();
    const inside = northOf(HOME, 20);
    tracker.update(inside.lat, inside.lng, [HOME]);

    const gone = northOf(HOME, 400);
    expect(tracker.update(gone.lat, gone.lng, [HOME])).toEqual({ kind: 'leave', place: HOME });
    // Already outside, so no repeat.
    expect(tracker.update(gone.lat, gone.lng, [HOME])).toBeNull();
  });

  it('can arrive somewhere else after leaving', () => {
    const tracker = createGeofenceTracker();
    const atHome = northOf(HOME, 20);
    tracker.update(atHome.lat, atHome.lng, [HOME, OFFICE]);

    const away = northOf(HOME, 400);
    expect(tracker.update(away.lat, away.lng, [HOME, OFFICE])).toEqual({ kind: 'leave', place: HOME });

    const atOffice = northOf(OFFICE, 25);
    expect(tracker.update(atOffice.lat, atOffice.lng, [HOME, OFFICE])).toEqual({
      kind: 'arrive',
      place: OFFICE,
    });
  });

  it('forgets a place that disappears from the list', () => {
    const tracker = createGeofenceTracker();
    const inside = northOf(HOME, 20);
    tracker.update(inside.lat, inside.lng, [HOME]);
    // Detection re-ran and dropped it; no phantom leave event.
    expect(tracker.update(inside.lat, inside.lng, [OFFICE])).toBeNull();
  });
});
