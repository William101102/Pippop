import { useMemo } from 'react';
import { Loader2, MapPin, Navigation } from 'lucide-react';
import { Avatar } from './Avatar';
import { fmtDist } from '../lib/format';
import { haversineKm } from '../lib/geo';
import type { Friend, LiveLocation, NearbyPlace } from '../types';

interface Props {
  friends: Friend[];
  myLocation: LiveLocation | null;
  places: NearbyPlace[];
  loading: boolean;
  onCheckIn: () => void;
  onSelectFriend: (friend: Friend) => void;
  onFocusPlace: (lat: number, lng: number) => void;
}

const CATEGORY_ICON: Record<string, string> = {
  cafe: '☕️', food: '🍜', park: '🌳', gym: '🏋️', shop: '🛍️', home: '🏠', work: '💼', other: '📍',
};

export function NearbyPanel({ friends, myLocation, places, loading, onCheckIn, onSelectFriend, onFocusPlace }: Props) {
  const ranked = useMemo(() => {
    if (!myLocation) return [];
    return friends
      .filter((f) => f.location)
      .map((f) => ({
        friend: f,
        distanceKm: haversineKm(myLocation.lat, myLocation.lng, f.location!.lat, f.location!.lng),
      }))
      .sort((a, b) => a.distanceKm - b.distanceKm);
  }, [friends, myLocation]);

  return (
    <div className="nearby-panel">
      <button className="primary wide" type="button" disabled={!myLocation} onClick={onCheckIn}>
        <MapPin size={17} /> Check in here
      </button>
      {!myLocation && <p className="muted empty-hint">Turn on location to see nearby people and places.</p>}

      {myLocation && (
        <>
          <div className="eyebrow">Closest friends</div>
          {ranked.length === 0 ? (
            <p className="muted empty-hint">No friends sharing their location yet.</p>
          ) : (
            <div className="friend-list">
              {ranked.map(({ friend, distanceKm }) => (
                <button className="friend-row" key={friend.id} type="button" onClick={() => onSelectFriend(friend)}>
                  <Avatar profile={friend} showStatus />
                  <div><b>{friend.display_name}</b><small>{friend.status_emoji} {friend.status_text}</small></div>
                  <span className="friend-meta"><Navigation size={12} /> {fmtDist(distanceKm)}</span>
                </button>
              ))}
            </div>
          )}

          <div className="eyebrow">Nearby places</div>
          {loading ? (
            <p className="muted empty-hint"><Loader2 size={14} className="spin" /> Finding nearby places…</p>
          ) : places.length === 0 ? (
            <p className="muted empty-hint">No check-ins nearby yet — be the first.</p>
          ) : (
            <div className="friend-list">
              {places.map((place) => (
                <button className="friend-row" key={place.id} type="button" onClick={() => onFocusPlace(place.lat, place.lng)}>
                  <span className="avatar place-avatar">{CATEGORY_ICON[place.category] || '📍'}</span>
                  <div><b>{place.name}</b><small>{place.address || 'User check-in spot'}</small></div>
                  <span className="friend-meta">{fmtDist(place.distanceKm)}</span>
                </button>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
