import { metresBetween } from './location';
import type { SignificantPlace } from './places';
import type { Zone } from '../types';

/** Inside this counts as "at" a place. Roughly a building plus its forecourt. */
const ARRIVE_RADIUS_M = 120;
/** Leaving needs more distance than arriving so a jittery fix cannot flap. */
const LEAVE_RADIUS_M = 200;

export interface GeofenceTransition {
  kind: 'arrive' | 'leave';
  place: SignificantPlace;
}

/**
 * Tracks which of the user's own significant places they are currently inside.
 *
 * This runs on the mover's device on purpose: significant places are private,
 * so nobody else's client could match a coordinate to "公司" in the first place.
 * The hysteresis between the two radii is what stops a stationary phone with a
 * drifting fix from emitting arrive/leave repeatedly.
 */
export function createGeofenceTracker() {
  let insideId: string | null = null;

  return {
    /** Returns a transition when one happened, otherwise null. */
    update(lat: number, lng: number, places: SignificantPlace[]): GeofenceTransition | null {
      const keyOf = (place: SignificantPlace) => `${place.kind}:${place.lat}:${place.lng}`;

      if (insideId) {
        const current = places.find((place) => keyOf(place) === insideId);
        if (!current) {
          insideId = null;
          return null;
        }
        const distance = metresBetween(current.lat, current.lng, lat, lng);
        if (distance > LEAVE_RADIUS_M) {
          insideId = null;
          return { kind: 'leave', place: current };
        }
        return null;
      }

      // Nearest first, so overlapping places resolve to the one you are really at.
      const nearest = places
        .map((place) => ({ place, distance: metresBetween(place.lat, place.lng, lat, lng) }))
        .sort((a, b) => a.distance - b.distance)[0];

      if (!nearest || nearest.distance > ARRIVE_RADIUS_M) return null;
      insideId = keyOf(nearest.place);
      return { kind: 'arrive', place: nearest.place };
    },
  };
}

export interface ZoneTransition {
  kind: 'arrive' | 'leave';
  zone: Zone;
}

/** Leaving needs a bit more distance than the zone's own radius, same
 *  hysteresis idea as the significant-place tracker above. */
const ZONE_LEAVE_PADDING_M = 60;

/**
 * Tracks which "Zenland" (a friend-visible, user-named zone) the device is
 * currently inside. Unlike significant places, zones carry their own radius
 * and are meant to be shared — the label just has to be resolved locally
 * because arrive/leave detection always runs on the mover's own device.
 */
export function createZoneGeofenceTracker() {
  let insideId: string | null = null;

  return {
    update(lat: number, lng: number, zones: Zone[]): ZoneTransition | null {
      if (insideId) {
        const current = zones.find((zone) => zone.id === insideId);
        if (!current) {
          insideId = null;
          return null;
        }
        const distance = metresBetween(current.lat, current.lng, lat, lng);
        if (distance > current.radius_m + ZONE_LEAVE_PADDING_M) {
          insideId = null;
          return { kind: 'leave', zone: current };
        }
        return null;
      }

      const nearest = zones
        .map((zone) => ({ zone, distance: metresBetween(zone.lat, zone.lng, lat, lng) }))
        .sort((a, b) => a.distance - b.distance)[0];

      if (!nearest || nearest.distance > nearest.zone.radius_m) return null;
      insideId = nearest.zone.id;
      return { kind: 'arrive', zone: nearest.zone };
    },
  };
}
