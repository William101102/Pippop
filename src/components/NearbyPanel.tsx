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
        <MapPin size={17} /> 在这里打卡
      </button>
      {!myLocation && <p className="muted empty-hint">先开启定位，才能看到附近的人和地点。</p>}

      {myLocation && (
        <>
          <div className="eyebrow">离你最近的朋友</div>
          {ranked.length === 0 ? (
            <p className="muted empty-hint">还没有朋友分享位置。</p>
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

          <div className="eyebrow">附近的地点</div>
          {loading ? (
            <p className="muted empty-hint"><Loader2 size={14} className="spin" /> 正在找附近的地点…</p>
          ) : places.length === 0 ? (
            <p className="muted empty-hint">附近还没有打卡过的地点，来当第一个吧。</p>
          ) : (
            <div className="friend-list">
              {places.map((place) => (
                <button className="friend-row" key={place.id} type="button" onClick={() => onFocusPlace(place.lat, place.lng)}>
                  <span className="avatar place-avatar">{CATEGORY_ICON[place.category] || '📍'}</span>
                  <div><b>{place.name}</b><small>{place.address || '用户打卡地点'}</small></div>
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
