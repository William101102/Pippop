import { useEffect, useRef } from 'react';
import L from 'leaflet';
import { esc, initials } from '../lib/format';
import type { Friend, LiveLocation, Profile } from '../types';

interface Props {
  me: Profile;
  friends: Friend[];
  myLocation: LiveLocation | null;
  onSelectFriend: (friend: Friend) => void;
  onSelectMe: () => void;
  focus?: { lat: number; lng: number } | null;
}

export function MapCanvas({ me, friends, myLocation, onSelectFriend, onSelectMe, focus }: Props) {
  const mapEl = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const layersRef = useRef<L.LayerGroup | null>(null);

  useEffect(() => {
    if (!mapEl.current || mapRef.current) return;
    const start: [number, number] = myLocation ? [myLocation.lat, myLocation.lng] : [37.33, -121.89];
    mapRef.current = L.map(mapEl.current, { zoomControl: false, attributionControl: false }).setView(start, 14);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(mapRef.current);
    layersRef.current = L.layerGroup().addTo(mapRef.current);
    setTimeout(() => mapRef.current?.invalidateSize(), 100);
    return () => { mapRef.current?.remove(); mapRef.current = null; };
  }, []);

  useEffect(() => {
    if (!layersRef.current) return;
    layersRef.current.clearLayers();
    const people: { p: Profile | Friend; l?: LiveLocation | null; mine?: boolean }[] = [
      { p: me, l: myLocation, mine: true },
      ...friends.map((f) => ({ p: f, l: f.location })),
    ];
    people.forEach(({ p, l, mine }) => {
      if (!l) return;
      const color = /^#[0-9a-f]{6}$/i.test(p.avatar_color) ? p.avatar_color : '#ff6658';
      const icon = L.divIcon({
        className: 'person-pin-shell',
        html: `<div class="person-pin ${mine ? 'mine' : ''}" style="--pin:${color}"><span>${esc(initials(p.display_name))}</span><b>${esc(p.status_emoji)}</b></div>`,
        iconSize: [58, 68],
        iconAnchor: [29, 64],
      });
      const marker = L.marker([l.lat, l.lng], { icon, zIndexOffset: mine ? 1000 : 0 }).addTo(layersRef.current!);
      marker.on('click', () => (mine ? onSelectMe() : onSelectFriend(p as Friend)));
    });
  }, [me, friends, myLocation, onSelectFriend, onSelectMe]);

  useEffect(() => {
    if (!focus || !mapRef.current) return;
    const z = mapRef.current.getZoom() < 14 ? 16 : mapRef.current.getZoom();
    const pt = mapRef.current.project(L.latLng(focus.lat, focus.lng), z);
    pt.y += 150;
    mapRef.current.flyTo(mapRef.current.unproject(pt, z), z, { duration: 0.65 });
  }, [focus]);

  return <div ref={mapEl} className="map" />;
}
