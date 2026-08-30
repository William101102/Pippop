import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import {
  BatteryCharging, Bell, Camera, ChevronDown, Footprints, Ghost, Loader2, LocateFixed,
  LogOut, MapPin, MessageCircle, Search, Share2, Sparkles, Star, Users, X,
} from 'lucide-react';
import { AddFriendPanel } from './components/AddFriendPanel';
import { Avatar } from './components/Avatar';
import { ChatPanel } from './components/ChatPanel';
import { CheckInPanel } from './components/CheckInPanel';
import { CompleteProfileScreen } from './components/CompleteProfileScreen';
import { FootprintsPanel } from './components/FootprintsPanel';
import { FriendRail } from './components/FriendRail';
import { NearbyPanel } from './components/NearbyPanel';
import { NotificationsPanel, type UnreadPreview } from './components/NotificationsPanel';
import { PersonCard } from './components/PersonCard';
import { RequestsInbox } from './components/RequestsInbox';
import { StatusEditor } from './components/StatusEditor';
import { GHOST_MODES, SHEET_OFFSET_PX } from './lib/constants';
import { fmtDist, fmtSpeed } from './lib/format';
import { friendShareText, haversineKm, inviteText, inviteUrl, shareText, usernameFromInviteUrl } from './lib/geo';
import { createGeofenceTracker } from './lib/geofence';
import { createFixGate, getCurrentFix, watchLocation } from './lib/location';
import { dismissSplash, getLaunchUrl, haptic, isNative, onAppResume, onAppUrlOpen, openAppSettings } from './lib/native';
import { clearPushBadge, registerPush, unregisterPush } from './lib/push';
import { isConfigured, supabase } from './lib/supabase';
import { publishWidgetSnapshot } from './lib/widget';
import { checkIn, loadMyVisits, loadNearbyPlaces } from './services/checkins';
import {
  loadMyReactions, loadPlaceEvents, recordPlaceEvent, sendReaction, setBestFriend,
} from './services/social';
import { loadFriendsBundle, respondFriendRequest, sendFriendRequest } from './services/friends';
import { getMyLastLocation, upsertMyLocation } from './services/locations';
import { uploadProfileAvatar } from './services/profile';
import {
  completeProfile, deleteMyAccount, getFriendGhostModes, getGhostMode, searchProfiles,
  setFriendGhostMode, setGhostMode as persistGhostMode, updateStatus,
} from './services/profiles';
import type {
  Friend, FriendRequest, GhostMode, HeatCell, LiveLocation, MapReaction, Message, NearbyPlace,
  Panel, PlaceCategory, PlaceEvent, Profile, Visit, VisitVisibility,
} from './types';
import { demoFriends, demoLocation, demoMe } from './dev/demo';
import { useBattery } from './hooks/useBattery';
import { useDraggableSheet } from './hooks/useDraggableSheet';
import { useMessages } from './hooks/useMessages';
import { useRealtime } from './hooks/useRealtime';
import { useSignificantPlaces } from './hooks/useSignificantPlaces';

const WORLD_CENTER: [number, number] = [20, 0];
const WORLD_ZOOM = 2;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CATEGORY_ICON: Record<string, string> = {
  cafe: '☕️', food: '🍜', park: '🌳', gym: '🏋️', shop: '🛍️', home: '🏠', work: '💼', other: '📍',
};

// Past this, a friend's pin is their last known spot rather than a live one.
const STALE_AFTER_MS = 30 * 60 * 1000;

/** The product is a phone app. Desktop only gets a device frame, not a website layout. */
function useBottomSheetLayout() {
  return true;
}

function ago(iso?: string) {
  if (!iso) return '暂无位置';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return '刚刚';
  if (mins < 60) return `${mins} 分钟前`;
  return `${Math.floor(mins / 60)} 小时前`;
}

function initials(name: string) { return name.trim().slice(0, 1).toUpperCase(); }
function safeHtml(value: string) {
  return value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]!);
}
function isUserUuid(id: string) { return UUID_RE.test(id); }

/** Reads the `?add=username` invite deep link once on boot. */
function readInviteQuery() {
  try {
    return usernameFromInviteUrl(window.location.href)
      || new URLSearchParams(window.location.search).get('add')?.trim()
      || '';
  } catch {
    return '';
  }
}

function AuthScreen({ onPreview }: { onPreview: () => void }) {
  const [signup, setSignup] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [username, setUsername] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!isConfigured) { setMessage('尚未配置 Supabase，请联系管理员。'); return; }
    if (signup && (!displayName.trim() || !username.trim())) { setMessage('请填写昵称和用户名。'); return; }
    setBusy(true);
    setMessage('');
    const result = signup
      ? await supabase.auth.signUp({
          email,
          password,
          options: { data: { display_name: displayName.trim(), username: username.trim().toLowerCase().replace(/[^a-z0-9_]/g, '') } },
        })
      : await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (result.error) setMessage(result.error.message);
    else if (signup && !result.data.session) setMessage('注册成功，请检查邮箱确认链接。');
  }

  return (
    <main className="auth-shell">
      <section className="auth-copy">
        <div className="auth-brand"><img src="./icons/icon-192.png" alt="" /><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>
        <div className="auth-hero-copy"><span className="hero-kicker">YOUR PEOPLE, RIGHT NOW</span><h1>地图不只是路。<br />是你们的世界。</h1><p>看看朋友在哪里、在做什么，然后一起出发。</p></div>
        <div className="floating-face face-one">🛹</div><div className="floating-face face-two">☕️</div><div className="floating-face face-three">🎧</div>
      </section>
      <section className="auth-card">
        <img className="mobile-auth-logo" src="./icons/icon-192.png" alt="Pinpop" />
        <div className="eyebrow">欢迎来到 PINPOP</div>
        <h2>{signup ? '创建你的世界' : '再次见到你真好'}</h2>
        <p className="muted">{signup ? '注册后添加朋友，一起点亮地图。' : '登录后继续看看朋友们在哪里。'}</p>
        {signup && (
          <div className="name-fields">
            <label>昵称<input value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="你的昵称" /></label>
            <label>用户名<input value={username} onChange={e => setUsername(e.target.value)} placeholder="your_id" /></label>
          </div>
        )}
        <label>邮箱<input value={email} onChange={e => setEmail(e.target.value)} type="email" placeholder="you@example.com" /></label>
        <label>密码<input value={password} onChange={e => setPassword(e.target.value)} type="password" placeholder="至少 6 位" /></label>
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? '请稍候…' : signup ? '注册' : '登录'}</button>
        <button className="text-button" type="button" onClick={() => setSignup(!signup)}>{signup ? '已经有账号？登录' : '第一次来？创建账号'}</button>
        <div className="rule"><span>或者</span></div>
        <button className="preview-button" type="button" onClick={onPreview}><Sparkles size={17} /> 先看看 App 长什么样</button>
      </section>
    </main>
  );
}

function App() {
  const [sessionReady, setSessionReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileLoaded, setProfileLoaded] = useState(false);
  const [preview, setPreview] = useState(() => {
    try {
      if (new URLSearchParams(window.location.search).has('preview')) return true;
    } catch { /* ignore */ }
    return document.body.classList.contains('phone-preview');
  });
  const [friends, setFriends] = useState<Friend[]>([]);
  const [requests, setRequests] = useState<FriendRequest[]>([]);
  const [requestBusy, setRequestBusy] = useState<Set<string>>(new Set());
  const [sentIds, setSentIds] = useState<Set<string>>(new Set());
  const [addResults, setAddResults] = useState<Profile[]>([]);
  const [inviteQuery, setInviteQuery] = useState('');
  const [location, setLocation] = useState<LiveLocation | null>(null);
  const [locationLabel, setLocationLabel] = useState<string | null>(null);
  const [panel, setPanel] = useState<Panel>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [ghostMode, setGhostMode] = useState<GhostMode>('precise');
  const [friendModes, setFriendModes] = useState<Record<string, GhostMode>>({});
  const [nearbyPlaces, setNearbyPlaces] = useState<NearbyPlace[]>([]);
  const [nearbyLoading, setNearbyLoading] = useState(false);
  const [myVisits, setMyVisits] = useState<Visit[]>([]);
  const [checkInOpen, setCheckInOpen] = useState(false);
  const [toast, setToast] = useState('');
  const [search, setSearch] = useState('');
  const [avatarBusy, setAvatarBusy] = useState(false);
  const [locating, setLocating] = useState(false);
  const [waving, setWaving] = useState(false);
  const [mapTileError, setMapTileError] = useState<string | null>(null);
  const [locationDenied, setLocationDenied] = useState(false);
  const [deleteArmed, setDeleteArmed] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [heatVisible, setHeatVisible] = useState(false);
  const [heatCells, setHeatCells] = useState<HeatCell[]>([]);
  const [myReactions, setMyReactions] = useState<MapReaction[]>([]);
  const [placeEvents, setPlaceEvents] = useState<PlaceEvent[]>([]);
  const isBottomSheet = useBottomSheetLayout();
  // Held in state, not a ref, so map init reliably fires on the render that mounts the node.
  const [mapNode, setMapNode] = useState<HTMLDivElement | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  // Separate layer so toggling the heatmap never rebuilds the person pins.
  const heatLayer = useRef<L.LayerGroup | null>(null);
  const tileLayerRef = useRef<L.TileLayer | null>(null);
  const didAutoFocus = useRef(false);
  const geofence = useRef(createGeofenceTracker());
  const locationRef = useRef<LiveLocation | null>(null);
  locationRef.current = location;
  const previewRef = useRef(preview);
  previewRef.current = preview;

  const liveId = preview ? undefined : profile?.id;
  const { places, recordFix } = useSignificantPlaces(liveId, Boolean(liveId));
  const {
    threads, unread, totalUnread, chatWith,
    openChat, closeChat, send, wave, waveAll, whatsUp, pushIncoming, refreshUnread,
  } = useMessages(liveId);
  useBattery(liveId);

  // Derived from the live friends list so the card updates as their pin moves,
  // instead of freezing the snapshot from the tap that opened it.
  const selected = useMemo(
    () => friends.find(f => f.id === selectedId) ?? null,
    [friends, selectedId],
  );

  // Single choke point for user-facing feedback, so it is also where the app
  // earns its haptics. Failures read as 失败/错误/不能/需要 in this codebase.
  const notify = useCallback((text: string) => {
    haptic(/失败|错误|不能|无法|需要先/.test(text) ? 'warning' : 'success');
    setToast(text);
    window.setTimeout(() => setToast(''), 3200);
  }, []);

  const switchPanel = useCallback((next: Panel) => {
    haptic('select');
    setSelectedId(null);
    setPanel(current => (current === next ? null : next));
  }, []);

  const reloadFriends = useCallback(async (userId: string) => {
    const bundle = await loadFriendsBundle(userId);
    setFriends(bundle.friends);
    setRequests(bundle.requests);
    setSentIds(bundle.sentIds);
  }, []);

  const handleFriendLocation = useCallback((userId: string, row: Record<string, unknown> | null) => {
    if (!row) return;
    setFriends(prev => prev.map(f => (
      f.id === userId ? { ...f, location: row as unknown as LiveLocation } : f
    )));
  }, []);

  const handleIncomingMessage = useCallback((msg: Message) => {
    pushIncoming(msg);
  }, [pushIncoming]);

  const handleReaction = useCallback((reaction: MapReaction) => {
    haptic('medium');
    setMyReactions(current => [reaction, ...current].slice(0, 30));
  }, []);

  const handlePlaceEvent = useCallback((event: PlaceEvent) => {
    setPlaceEvents(current => [event, ...current].slice(0, 40));
  }, []);

  useRealtime({
    meId: liveId,
    onFriendsChange: () => {
      if (profile?.id) reloadFriends(profile.id).catch(() => undefined);
    },
    onFriendLocation: handleFriendLocation,
    onMessage: handleIncomingMessage,
    onReaction: handleReaction,
    onPlaceEvent: handlePlaceEvent,
  });

  useEffect(() => {
    const invite = readInviteQuery();
    if (invite) setInviteQuery(invite);
    try {
      if (invite) window.history.replaceState({}, '', window.location.pathname + window.location.hash);
    } catch {
      // history rewriting is cosmetic
    }
    const apply = (url: string) => {
      const name = usernameFromInviteUrl(url);
      if (name) setInviteQuery(name);
    };
    void getLaunchUrl().then(apply);
    return onAppUrlOpen(apply);
  }, []);

  // Feed own fixes into private overnight-place history.
  useEffect(() => {
    if (preview || !location || !profile) return;
    recordFix(location.lat, location.lng, location.updated_at).catch(() => undefined);
  }, [preview, location, profile, recordFix]);

  // Arrival notices are detected here rather than on the viewer's device,
  // because significant places are private: only this client can tell that a
  // coordinate means "公司". Frozen mode should not broadcast movement at all.
  useEffect(() => {
    if (preview || !location || !profile || places.length === 0) return;
    if (ghostMode === 'frozen') return;
    const transition = geofence.current.update(location.lat, location.lng, places);
    if (!transition) return;
    recordPlaceEvent(
      profile.id,
      transition.kind,
      transition.place.label,
      transition.place.lat,
      transition.place.lng,
    ).catch(() => undefined);
  }, [location, profile, places, ghostMode]);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSignedIn(Boolean(data.session)); setSessionReady(true); });
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      setSignedIn(Boolean(next));
      setSessionReady(true);
      if (!next && !previewRef.current) {
        setProfile(null);
        setProfileLoaded(false);
        setFriends([]);
        setRequests([]);
        setLocation(null);
        setLocationLabel(null);
        setMyVisits([]);
        setNearbyPlaces([]);
        setFriendModes({});
        setPanel(null);
        didAutoFocus.current = false;
      }
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (preview) {
      setProfile(demoMe);
      setFriends(demoFriends);
      setLocation(demoLocation);
      setProfileLoaded(true);
      setSessionReady(true);
      setPanel(null);
      return;
    }
    if (!signedIn) {
      setProfile(null);
      setProfileLoaded(false);
      return;
    }
    setProfileLoaded(false);
    (async () => {
      const { data: user } = await supabase.auth.getUser();
      if (!user.user) {
        setProfileLoaded(true);
        return;
      }
      const { data: nextProfile } = await supabase.from('profiles').select('*').eq('id', user.user.id).maybeSingle();
      setProfile(nextProfile as Profile | null);
      if (nextProfile) {
        const saved = await getMyLastLocation(user.user.id).catch(() => null);
        if (saved) {
          setLocation(saved as LiveLocation);
          setLocationLabel('上次保存的位置');
        }
        await reloadFriends(user.user.id);
        getGhostMode(user.user.id).then(setGhostMode).catch(() => undefined);
        getFriendGhostModes(user.user.id).then(setFriendModes).catch(() => undefined);
        loadMyVisits(user.user.id).then(setMyVisits).catch(() => undefined);
      }
      setProfileLoaded(true);
    })();
  }, [signedIn, reloadFriends, preview]);

  // Open the add-friend sheet automatically when arriving from an invite link.
  useEffect(() => {
    if (inviteQuery && profile) setPanel('add');
  }, [inviteQuery, profile]);

  useEffect(() => {
    if (!signedIn || !profile) return;
    const gate = createFixGate();
    return watchLocation(
      (fix) => {
        const next: LiveLocation = {
          user_id: profile.id,
          lat: fix.lat,
          lng: fix.lng,
          accuracy: fix.accuracy,
          speed: fix.speed,
          updated_at: new Date().toISOString(),
        };
        setLocation(next);
        setLocationLabel(null);
        setLocationDenied(false);
        if (!isUserUuid(profile.id) || ghostMode === 'frozen') return;
        if (!gate.shouldPersist(fix)) return;
        gate.commit(fix);
        upsertMyLocation(next).catch(() => undefined);
      },
      () => setLocationDenied(true),
    );
  }, [signedIn, profile, ghostMode]);

  const focusMapOn = useCallback((lat: number, lng: number, zoom = 16) => {
    if (!map.current) return;
    const z = map.current.getZoom() < 14 ? zoom : map.current.getZoom();
    const pt = map.current.project(L.latLng(lat, lng), z);
    pt.y += SHEET_OFFSET_PX;
    map.current.flyTo(map.current.unproject(pt, z), z, { animate: true, duration: 0.8 });
  }, []);

  const openFriend = useCallback((friend: Friend) => {
    haptic('select');
    setSelectedId(friend.id);
    setPanel(null);
    if (friend.location) focusMapOn(friend.location.lat, friend.location.lng);
  }, [focusMapOn]);

  useEffect(() => {
    if (!mapNode || map.current) return;
    const start: [number, number] = locationRef.current
      ? [locationRef.current.lat, locationRef.current.lng]
      : WORLD_CENTER;
    const zoom = locationRef.current ? 14 : WORLD_ZOOM;
    const instance = L.map(mapNode, { zoomControl: false, attributionControl: true }).setView(start, zoom);
    map.current = instance;

    const tileLayer = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      crossOrigin: true,
      attribution: '&copy; OpenStreetMap contributors',
    });
    let failures = 0;
    tileLayer.on('tileerror', () => {
      failures += 1;
      // A couple of dropped tiles at the edge of the viewport is normal; only warn on sustained failure.
      if (failures >= 4) setMapTileError('地图瓦片加载失败，请检查网络后刷新页面。');
    });
    tileLayer.on('load', () => {
      failures = 0;
      setMapTileError(null);
    });
    tileLayer.addTo(instance);
    tileLayerRef.current = tileLayer;
    // Heat sits under the pins so avatars stay legible on top of it.
    heatLayer.current = L.layerGroup().addTo(instance);
    layers.current = L.layerGroup().addTo(instance);

    const resize = () => instance.invalidateSize();
    const observer = new ResizeObserver(resize);
    observer.observe(mapNode);
    window.addEventListener('resize', resize);
    // Leaflet needs a size recheck once the sheet/dock layout settles.
    const t1 = window.setTimeout(resize, 60);
    const t2 = window.setTimeout(resize, 400);
    setMapReady(true);

    return () => {
      window.clearTimeout(t1);
      window.clearTimeout(t2);
      observer.disconnect();
      window.removeEventListener('resize', resize);
      tileLayerRef.current = null;
      heatLayer.current = null;
      layers.current = null;
      map.current = null;
      setMapReady(false);
      instance.remove();
    };
  }, [mapNode]);

  useEffect(() => {
    if (!location || !mapReady || didAutoFocus.current) return;
    didAutoFocus.current = true;
    focusMapOn(location.lat, location.lng);
  }, [location, mapReady, focusMapOn]);

  // Hold the native splash until a real screen is behind it, so launch never
  // flashes an empty map. Sign-in and profile setup never mount a map, so those
  // count as ready too, and a timeout guarantees the splash cannot wedge the app
  // if any of those signals never arrive.
  const firstScreenReady =
    mapReady || (sessionReady && !signedIn) || (sessionReady && profileLoaded && !profile);
  useEffect(() => {
    if (firstScreenReady) dismissSplash();
  }, [firstScreenReady]);
  useEffect(() => {
    const bail = window.setTimeout(dismissSplash, 4000);
    return () => window.clearTimeout(bail);
  }, []);

  // Friends' pins go stale while the app is suspended and realtime is dropped,
  // so treat coming back to the foreground as a refresh.
  useEffect(() => {
    if (preview || !profile?.id) return;
    const meId = profile.id;
    const refresh = () => {
      reloadFriends(meId).catch(() => undefined);
      refreshUnread();
      loadMyReactions(meId).then(setMyReactions).catch(() => undefined);
      loadPlaceEvents().then(setPlaceEvents).catch(() => undefined);
      clearPushBadge();
    };
    refresh();
    return onAppResume(refresh);
  }, [preview, profile?.id, reloadFriends, refreshUnread]);

  useEffect(() => {
    publishWidgetSnapshot(friends).catch(() => undefined);
  }, [friends]);

  // Registered only once there is a profile, so the single permission prompt
  // iOS allows is spent on someone who has actually finished signing up.
  useEffect(() => {
    if (preview || !profile?.id) return;
    let cleanup: (() => void) | undefined;
    registerPush(profile.id).then((fn) => { cleanup = fn; });
    return () => cleanup?.();
  }, [preview, profile?.id]);

  // Only the newest reaction from the last few minutes rides along on the pin;
  // older ones stay in the notifications feed.
  const freshReaction = useMemo(() => {
    const recent = myReactions.find(
      r => Date.now() - new Date(r.created_at).getTime() < 5 * 60_000,
    );
    return recent?.emoji;
  }, [myReactions]);

  useEffect(() => {
    if (!mapReady || !layers.current || !profile) return;
    layers.current.clearLayers();
    const people: { p: Profile | Friend; l?: LiveLocation | null; mine?: boolean }[] = [
      { p: profile, l: location, mine: true },
      ...friends.map(p => ({ p, l: p.location })),
    ];
    people.forEach(({ p, l, mine }) => {
      if (!l) return;
      const color = /^#[0-9a-f]{6}$/i.test(p.avatar_color) ? p.avatar_color : '#ff6658';
      const face = p.avatar_url
        ? `<img src="${safeHtml(p.avatar_url)}" alt="" referrerpolicy="no-referrer">`
        : `<span>${safeHtml(initials(p.display_name))}</span>`;
      // Green ring = this person is sharing a live fix. Gray ring = they froze
      // sharing, or their last ping is old enough that it is only a last-seen.
      const hidden = (mine ? ghostMode : p.ghost_mode) === 'frozen';
      const stale = Date.now() - new Date(l.updated_at).getTime() > STALE_AFTER_MS;
      const live = !hidden && !stale;
      const reaction = mine ? freshReaction : undefined;
      const moving = fmtSpeed(l.speed);
      const icon = L.divIcon({
        className: 'person-pin-shell',
        html: `<div class="person-pin ${mine ? 'mine' : ''} ${live ? 'live' : 'away'}" style="--pin:${color}"><div class="pin-face">${face}</div><b>${safeHtml(p.status_emoji)}</b>${live ? (moving ? `<i class="pin-speed">${safeHtml(moving)}</i>` : '') : `<i>${safeHtml(ago(l.updated_at))}</i>`}${reaction ? `<u class="pin-reaction">${safeHtml(reaction)}</u>` : ''}</div>`,
        iconSize: [70, 82],
        iconAnchor: [35, 76],
      });
      const marker = L.marker([l.lat, l.lng], { icon, zIndexOffset: mine ? 1000 : 0 }).addTo(layers.current!);
      if (!mine) marker.on('click', () => { const f = friends.find(x => x.id === p.id); if (f) openFriend(f); });
    });
    // Private overnight places, visible only to the signed-in user.
    places.forEach(p => {
      const icon = L.divIcon({
        className: 'place-pin-shell',
        html: `<div class="place-pin" style="--place:#25c9b7"><span>🌙</span><b>${safeHtml(`${p.score} 晚`)}</b></div>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      L.marker([p.lat, p.lng], { icon, interactive: false, zIndexOffset: -500 }).addTo(layers.current!);
    });
    // Check-in pins, so the nearby list and the map agree.
    nearbyPlaces.forEach(p => {
      const icon = L.divIcon({
        className: 'place-pin-shell',
        html: `<div class="place-pin checkin" style="--place:#5b35f2"><span>${CATEGORY_ICON[p.category] || '📍'}</span><b>${safeHtml(p.name)}</b></div>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      L.marker([p.lat, p.lng], { icon, interactive: false, zIndexOffset: -400 }).addTo(layers.current!);
    });
  }, [friends, location, profile, places, nearbyPlaces, mapReady, freshReaction, openFriend, ghostMode]);

  // Plain circles rather than a heatmap plugin: with history bucketed into grid
  // cells server side, one translucent circle per cell already reads as heat and
  // keeps the bundle from growing for a single overlay.
  useEffect(() => {
    if (!mapReady || !heatLayer.current) return;
    const group = heatLayer.current;
    group.clearLayers();
    if (!heatVisible || heatCells.length === 0) return;

    const busiest = Math.max(...heatCells.map(c => c.hits));
    heatCells.forEach(cell => {
      // Square-root keeps a single very frequent cell from flattening the rest.
      const weight = Math.sqrt(cell.hits / busiest);
      L.circleMarker([cell.lat, cell.lng], {
        radius: 9 + weight * 15,
        stroke: false,
        fillColor: weight > 0.66 ? '#ff3f8e' : weight > 0.33 ? '#ff8a3d' : '#ffd34e',
        fillOpacity: 0.16 + weight * 0.4,
        interactive: false,
      }).addTo(group);
    });
  }, [heatVisible, heatCells, mapReady]);

  const refreshNearby = useCallback(async () => {
    const current = locationRef.current;
    if (!current) return;
    setNearbyLoading(true);
    try {
      setNearbyPlaces(await loadNearbyPlaces(current.lat, current.lng));
    } catch {
      // nearby places are best-effort
    } finally {
      setNearbyLoading(false);
    }
  }, []);

  useEffect(() => {
    if (panel !== 'places' || !location) return;
    refreshNearby();
  }, [panel, location, refreshNearby]);

  async function locateMe() {
    if (locating || !profile) return;
    haptic('light');
    if (location) {
      map.current?.flyTo([location.lat, location.lng], 16, { animate: true, duration: 0.8 });
      return;
    }
    setLocating(true);
    try {
      const fix = await getCurrentFix();
      const next: LiveLocation = {
        user_id: profile.id,
        lat: fix.lat,
        lng: fix.lng,
        accuracy: fix.accuracy,
        speed: fix.speed,
        updated_at: new Date().toISOString(),
      };
      setLocation(next);
      setLocationLabel(null);
      if (isUserUuid(profile.id) && ghostMode !== 'frozen') {
        await upsertMyLocation(next).catch(() => undefined);
      }
      map.current?.flyTo([next.lat, next.lng], 16, { animate: true, duration: 0.8 });
    } catch (error) {
      const saved = isUserUuid(profile.id) ? await getMyLastLocation(profile.id).catch(() => null) : null;
      if (saved) {
        setLocation(saved as LiveLocation);
        setLocationLabel('上次保存的位置');
        map.current?.flyTo([saved.lat, saved.lng], 16, { animate: true, duration: 0.8 });
        notify('无法获取当前位置，已回到上次保存的位置');
        return;
      }
      const denied = error instanceof GeolocationPositionError && error.code === error.PERMISSION_DENIED;
      if (denied && isNative) notify('请在系统设置中允许 Pinpop 使用位置');
      else if (denied) notify('请在浏览器设置中允许 Pinpop 使用位置信息');
      else notify('暂时无法获取位置，请开启定位权限后重试');
    } finally {
      setLocating(false);
    }
  }

  async function changeAvatar(file?: File) {
    if (!file || !profile) return;
    setAvatarBusy(true);
    try {
      const avatarUrl = await uploadProfileAvatar(profile.id, file);
      setProfile(current => current ? { ...current, avatar_url: avatarUrl } : current);
      notify('新头像已经换好啦 ✨');
    } catch (error) {
      notify(error instanceof Error ? error.message : '头像上传失败，请稍后再试');
    } finally {
      setAvatarBusy(false);
    }
  }

  async function respondToRequest(relId: string, status: 'accepted' | 'declined') {
    if (!profile) return;
    setRequestBusy(prev => new Set(prev).add(relId));
    try {
      await respondFriendRequest(relId, status);
      await reloadFriends(profile.id);
      notify(status === 'accepted' ? '你们已经是好友啦 🎉' : '已忽略该请求');
    } catch (error) {
      notify(error instanceof Error ? error.message : '操作失败，请稍后再试');
    } finally {
      setRequestBusy(prev => { const next = new Set(prev); next.delete(relId); return next; });
    }
  }

  async function changeGhostMode(mode: GhostMode) {
    if (!profile) return;
    const previous = ghostMode;
    setGhostMode(mode);
    try {
      await persistGhostMode(profile.id, mode, location ? { lat: location.lat, lng: location.lng } : undefined);
      const label = GHOST_MODES.find(m => m.value === mode)?.title ?? mode;
      notify(`已切换为${label}，朋友看到的位置由服务端处理`);
    } catch (error) {
      setGhostMode(previous);
      notify(error instanceof Error ? error.message : '隐私设置保存失败');
    }
  }

  async function changeFriendMode(friendId: string, mode: GhostMode | null) {
    if (!profile) return;
    const previous = friendModes;
    setFriendModes(current => {
      const next = { ...current };
      if (mode) next[friendId] = mode;
      else delete next[friendId];
      return next;
    });
    try {
      await setFriendGhostMode(profile.id, friendId, mode);
    } catch (error) {
      setFriendModes(previous);
      notify(error instanceof Error ? error.message : '单独设置保存失败');
    }
  }

  async function saveStatus(emoji: string, text: string) {
    if (!profile) return { error: '登录状态已失效' };
    try {
      await updateStatus(profile.id, emoji, text);
      setProfile(current => current ? { ...current, status_emoji: emoji, status_text: text } : current);
      notify('状态已更新');
      return {};
    } catch (error) {
      return { error: error instanceof Error ? error.message : '状态保存失败' };
    }
  }

  async function signOut() {
    // Drop the push token first, or a shared device keeps getting this user's
    // notifications after they hand it over.
    if (profile) await unregisterPush(profile.id).catch(() => undefined);
    await supabase.auth.signOut();
  }

  async function toggleBestFriend(friend: Friend) {
    if (!profile) return;
    const pinned = !friend.is_best_friend;
    haptic(pinned ? 'success' : 'light');
    // Optimistic, and re-sorted the same way the server bundle arrives.
    setFriends(current => current
      .map(f => (f.id === friend.id ? { ...f, is_best_friend: pinned } : f))
      .sort((a, b) => {
        if (a.is_best_friend !== b.is_best_friend) return a.is_best_friend ? -1 : 1;
        return (b.streak_days ?? 0) - (a.streak_days ?? 0);
      }));
    try {
      await setBestFriend(profile.id, friend.id, pinned);
    } catch (error) {
      setFriends(current => current.map(f => (f.id === friend.id ? { ...f, is_best_friend: !pinned } : f)));
      notify(error instanceof Error ? error.message : '操作失败');
    }
  }

  async function reactTo(friend: Friend, emoji: string) {
    if (!profile) return;
    haptic('medium');
    try {
      await sendReaction(profile.id, friend.id, emoji);
      notify(`已给 ${friend.display_name} 发了 ${emoji}`);
    } catch (error) {
      notify(error instanceof Error ? error.message : '表情没发出去');
    }
  }

  async function confirmDeleteAccount() {
    setDeleting(true);
    try {
      await deleteMyAccount();
      // The auth listener tears down the rest of the state on sign-out.
      setDeleteArmed(false);
    } catch (error) {
      notify(error instanceof Error ? error.message : '删除失败，请稍后再试');
    } finally {
      setDeleting(false);
    }
  }

  async function shareCard(target: Profile | Friend) {
    const mine = target.id === profile?.id;
    const text = mine
      ? inviteText(target.username, target.display_name)
      : friendShareText(target.username, target.display_name);
    const result = await shareText(
      mine ? 'Pinpop 好友邀请' : `在 Pinpop 上加 ${target.display_name}`,
      text,
      inviteUrl(target.username),
    );
    if (result === 'cancelled') return;
    notify(result === 'shared' ? '已分享 ✨' : '链接已复制，发给朋友就能加好友');
  }

  async function waveAtEveryone() {
    if (!profile || waving) return;
    if (!friends.length) {
      notify('先加几个朋友，再一起挥手吧');
      setPanel('add');
      return;
    }
    setWaving(true);
    try {
      const result = await waveAll(friends.map(f => f.id));
      notify(result.failed
        ? `已向 ${result.sent} 位朋友挥手，${result.failed} 位失败`
        : `已向 ${result.sent} 位朋友挥手 👋`);
    } finally {
      setWaving(false);
    }
  }

  async function submitCheckIn(input: {
    name: string;
    category: PlaceCategory;
    address?: string | null;
    visibility: VisitVisibility;
    note?: string;
  }) {
    if (!profile || !location) return { error: '需要先定位才能打卡' };
    const result = await checkIn(profile.id, { ...input, lat: location.lat, lng: location.lng });
    if (result.error) return { error: result.error };
    setCheckInOpen(false);
    notify('打卡成功 📍');
    loadMyVisits(profile.id).then(setMyVisits).catch(() => undefined);
    refreshNearby();
    return {};
  }

  const filtered = useMemo(
    () => friends.filter(f => `${f.display_name} ${f.username}`.toLowerCase().includes(search.toLowerCase())),
    [friends, search],
  );

  const friendIds = useMemo(() => new Set(friends.map(f => f.id)), [friends]);
  const chatFriend = useMemo(
    () => (chatWith ? friends.find(f => f.id === chatWith) ?? null : null),
    [chatWith, friends],
  );

  const unreadPreviews = useMemo<UnreadPreview[]>(
    () => friends
      .filter(f => (unread[f.id] || 0) > 0)
      .map(f => {
        const thread = threads[f.id] || [];
        return { friend: f, count: unread[f.id], last: thread[thread.length - 1] };
      }),
    [friends, unread, threads],
  );

  const notificationCount = requests.length + totalUnread + myReactions.length;

  const nearest = useMemo(() => {
    if (!location) return null;
    let best: { friend: Friend; km: number } | null = null;
    for (const f of friends) {
      if (!f.location) continue;
      const km = haversineKm(location.lat, location.lng, f.location.lat, f.location.lng);
      if (!best || km < best.km) best = { friend: f, km };
    }
    return best;
  }, [friends, location]);

  // The sheet only becomes a draggable bottom sheet at the width where the CSS
  // actually docks it to the bottom edge.
  const sheetDrag = useDraggableSheet({
    onDismiss: () => setPanel(null),
    enabled: isBottomSheet,
  });

  if (!sessionReady && !preview) {
    return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;
  }
  if (!signedIn && !preview) return <AuthScreen onPreview={() => setPreview(true)} />;
  if (!profileLoaded) {
    return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;
  }
  if (!profile) {
    return (
      <CompleteProfileScreen onComplete={async (username, displayName) => {
        const { data: user } = await supabase.auth.getUser();
        if (!user.user) return { error: '登录状态已失效，请重新登录' };
        const result = await completeProfile(user.user.id, username, displayName);
        if (result.error) return { error: result.error };
        if (result.profile) setProfile(result.profile);
        return {};
      }} />
    );
  }

  const sheetCopy: Record<string, { eyebrow: string; title: string }> = {
    friends: { eyebrow: '你的圈子', title: `${friends.length} 位朋友` },
    places: { eyebrow: '身边正在发生', title: '探索附近' },
    world: { eyebrow: '你的世界', title: '我的资料' },
    messages: { eyebrow: '保持联系', title: '消息' },
    settings: { eyebrow: '位置隐私', title: 'Ghost Mode' },
    notifications: { eyebrow: '最新动态', title: '通知' },
  };
  const copy = panel ? sheetCopy[panel] : undefined;

  return (
    <main className="app-shell">
      <div ref={setMapNode} className="map" />
      {mapTileError && <div className="map-error-banner">{mapTileError}</div>}
      {!location && (
        <div className="map-hint">
          {locationDenied ? (
            <>
              <p>定位权限被拒绝了，朋友看不到你的位置。{isNative ? '到系统设置里允许「使用期间」或「始终」即可。' : '请在浏览器地址栏的权限里重新允许定位。'}</p>
              {isNative ? (
                <button type="button" className="primary compact" onClick={() => { haptic('light'); openAppSettings(); }}>
                  打开设置
                </button>
              ) : (
                <button type="button" className="primary compact" onClick={locateMe} disabled={locating}>
                  {locating ? '定位中…' : '重试定位'}
                </button>
              )}
            </>
          ) : (
            <>
              <p>开启定位后，你的位置会显示在地图上。</p>
              <button type="button" className="primary compact" onClick={() => { haptic('light'); locateMe(); }} disabled={locating}>
                {locating ? '定位中…' : '开启定位'}
              </button>
            </>
          )}
        </div>
      )}
      {locationLabel && <div className="location-label">{locationLabel}</div>}

      {nearest && !selected && !panel && (
        <button className="map-mood" type="button" onClick={() => openFriend(nearest.friend)}>
          <span>{nearest.friend.status_emoji} {nearest.friend.display_name}</span>
          <b>{fmtDist(nearest.km)}</b>
          <small>{ago(nearest.friend.location?.updated_at)}</small>
        </button>
      )}

      <header className="topbar">
        <button className="profile-chip" type="button" onClick={() => setPanel('world')}>
          <Avatar profile={profile} />
          <div><b>{profile.display_name}</b><small>{profile.status_emoji} {profile.status_text}</small></div>
          <ChevronDown size={16} />
        </button>
        <div className="top-actions">
          {preview && (
            <button className="demo-badge" type="button" onClick={() => setPreview(false)}>预览</button>
          )}
          <button className="circle-button" type="button" onClick={() => setPanel('notifications')} aria-label="通知">
            <Bell size={20} />
            {notificationCount > 0 && <span className="dot-badge">{notificationCount > 9 ? '9+' : notificationCount}</span>}
          </button>
          <button className={`circle-button ${ghostMode !== 'precise' ? 'active' : ''}`} type="button" onClick={() => setPanel('settings')}><Ghost size={21} /></button>
        </div>
      </header>

      <div className="map-tools">
        <button type="button" onClick={locateMe} disabled={locating} aria-label="定位到我">
          {locating ? <Loader2 size={21} className="spin" /> : <LocateFixed size={21} />}
        </button>
        <button type="button" onClick={() => setPanel('places')} aria-label="探索附近"><MapPin size={21} /></button>
      </div>

      <nav className="dock">
        <button className={panel === 'friends' ? 'active' : ''} type="button" onClick={() => switchPanel('friends')}><Users /><span>朋友</span></button>
        <button className={panel === 'places' ? 'active' : ''} type="button" onClick={() => switchPanel('places')}><Search /><span>探索</span></button>
        <button className="center-action" type="button" disabled={waving} onClick={() => { haptic('heavy'); waveAtEveryone(); }} aria-label="向所有朋友挥手">
          <span>{waving ? '…' : '👋'}</span>
        </button>
        <button className={panel === 'world' ? 'active' : ''} type="button" onClick={() => switchPanel('world')}><Footprints /><span>足迹</span></button>
        <button className={panel === 'messages' ? 'active' : ''} type="button" onClick={() => switchPanel('messages')}>
          <MessageCircle /><span>消息</span>
          {totalUnread > 0 && <span className="dot-badge">{totalUnread > 9 ? '9+' : totalUnread}</span>}
        </button>
      </nav>

      {!panel && !selected && !chatFriend && (
        <div className="map-peek">
          <FriendRail
            me={profile}
            friends={friends}
            unread={unread}
            activeId={null}
            onSelectMe={() => { setSelectedId(null); if (location) focusMapOn(location.lat, location.lng); else locateMe(); }}
            onSelectFriend={openFriend}
            onAddFriend={() => setPanel('add')}
          />
        </div>
      )}

      {panel === 'add' && (
        <AddFriendPanel
          me={profile}
          results={addResults}
          sentIds={sentIds}
          friendIds={friendIds}
          initialQuery={inviteQuery}
          onClose={() => { setInviteQuery(''); setPanel('friends'); }}
          onSearch={(q) => { searchProfiles(profile.id, q).then(setAddResults).catch(() => undefined); }}
          onSendRequest={async (id) => {
            const outcome = await sendFriendRequest(profile.id, id);
            if (outcome === 'accepted') {
              await reloadFriends(profile.id);
              notify('对方之前也加过你，现在你们是好友啦 🎉');
              return;
            }
            setSentIds(prev => new Set(prev).add(id));
            notify(outcome === 'already_friends' ? '你们已经是好友了' : '好友请求已发送');
          }}
          onNotify={notify}
        />
      )}

      {checkInOpen && location && (
        <CheckInPanel location={location} onClose={() => setCheckInOpen(false)} onSubmit={submitCheckIn} />
      )}

      {panel && panel !== 'add' && copy && (
        <aside className={`sheet ${sheetDrag.sheetProps.className}`} style={sheetDrag.sheetProps.style}>
          <div className="grabber-hit" {...sheetDrag.handleProps}><div className="grabber" /></div>
          <div className="sheet-head">
            <div>
              <div className="eyebrow">{copy.eyebrow}</div>
              <h2>{copy.title}</h2>
            </div>
            <button className="close-button" type="button" onClick={() => setPanel(null)}><X size={19} /></button>
          </div>

          {panel === 'friends' && (
            <>
              <RequestsInbox requests={requests} busyIds={requestBusy} onRespond={respondToRequest} />
              <FriendRail
                me={profile}
                friends={friends}
                unread={unread}
                activeId={selected?.id ?? null}
                onSelectMe={() => { setSelectedId(null); if (location) focusMapOn(location.lat, location.lng); else locateMe(); }}
                onSelectFriend={openFriend}
                onAddFriend={() => setPanel('add')}
              />
              <div className="search"><Search size={18} /><input placeholder="搜索朋友" value={search} onChange={e => setSearch(e.target.value)} /></div>
              <div className="friend-list">
                {filtered.length === 0 && (
                  <div className="empty-state">
                    <span className="empty-art">{friends.length ? '🔍' : '👋'}</span>
                    {friends.length ? (
                      <>
                        <b>没有匹配的朋友</b>
                        <p>试试别的名字，或者用 @用户名 搜索。</p>
                      </>
                    ) : (
                      <>
                        <b>还没有朋友</b>
                        <p>把你的名片链接发给朋友，他们点开就能直接加你。</p>
                        <button className="primary compact" type="button" onClick={() => setPanel('add')}>添加朋友</button>
                      </>
                    )}
                  </div>
                )}
                {filtered.map(f => (
                  <button className="friend-row" key={f.id} type="button" onClick={() => openFriend(f)}>
                    <Avatar profile={f} showStatus />
                    <div>
                      <b>
                        {f.is_best_friend && <Star size={12} className="best-star" />}
                        {f.display_name}
                        {(f.streak_days ?? 0) > 0 && <i className="streak-chip">🔥{f.streak_days}</i>}
                      </b>
                      <small>@{f.username} · {f.status_text}</small>
                    </div>
                    <div className="friend-meta">
                      <span>
                        {location && f.location
                          ? fmtDist(haversineKm(location.lat, location.lng, f.location.lat, f.location.lng))
                          : ago(f.location?.updated_at)}
                      </span>
                      <small>{f.is_charging && <BatteryCharging size={13} />} {f.battery_level != null ? `${f.battery_level}%` : ''}</small>
                    </div>
                  </button>
                ))}
              </div>
              <button className="share-card-button" type="button" onClick={() => shareCard(profile)}>
                <Share2 size={16} />
                <div><b>分享我的名片</b><small>朋友点开链接就能直接加你</small></div>
              </button>
            </>
          )}

          {panel === 'places' && (
            <NearbyPanel
              friends={friends}
              myLocation={location}
              places={nearbyPlaces}
              loading={nearbyLoading}
              onCheckIn={() => setCheckInOpen(true)}
              onSelectFriend={openFriend}
              onFocusPlace={focusMapOn}
            />
          )}

          {panel === 'notifications' && (
            <NotificationsPanel
              requests={requests}
              unreadPreviews={unreadPreviews}
              reactions={myReactions}
              placeEvents={placeEvents}
              friends={friends}
              busyIds={requestBusy}
              onRespond={respondToRequest}
              onOpenChat={(id) => { openChat(id); setPanel(null); }}
              onFocusEvent={(lat, lng) => { setPanel(null); focusMapOn(lat, lng); }}
            />
          )}

          {panel === 'world' && (
            <div className="world-panel">
              <div className="profile-spotlight">
                <div className="avatar-editor">
                  <Avatar profile={profile} className="profile-avatar" showStatus />
                  <label className={avatarBusy ? 'uploading' : ''}>
                    <Camera size={16} />
                    <span>{avatarBusy ? '上传中…' : '换头像'}</span>
                    <input type="file" accept="image/jpeg,image/png,image/webp" disabled={avatarBusy} onChange={e => changeAvatar(e.target.files?.[0])} />
                  </label>
                </div>
                <div><span>@{profile.username}</span><strong>{profile.display_name}</strong><small>让朋友一眼就在地图上找到你</small></div>
              </div>

              <button className="share-card-button" type="button" onClick={() => shareCard(profile)}>
                <Share2 size={16} />
                <div><b>分享我的名片</b><small>发链接给朋友，点开就能加你</small></div>
              </button>

              <StatusEditor profile={profile} onSave={saveStatus} />

              <div className="eyebrow">我的打卡</div>
              {myVisits.length === 0 ? (
                <p className="muted empty-hint">还没有打卡记录，去「探索」里打个卡吧。</p>
              ) : (
                <div className="friend-list">
                  {myVisits.map(visit => (
                    <button
                      className="friend-row"
                      type="button"
                      key={visit.id}
                      onClick={() => visit.place && focusMapOn(visit.place.lat, visit.place.lng)}
                    >
                      <span className="avatar place-avatar">{CATEGORY_ICON[visit.place?.category || 'other'] || '📍'}</span>
                      <div>
                        <b>{visit.place?.name || '未知地点'}</b>
                        <small>{visit.note || (visit.visibility === 'private' ? '仅自己可见' : '好友可见')}</small>
                      </div>
                      <span className="friend-meta">{ago(visit.arrived_at)}</span>
                    </button>
                  ))}
                </div>
              )}

              <div className="eyebrow">足迹与热力图</div>
              <FootprintsPanel
                heatVisible={heatVisible}
                onToggleHeat={(next) => { haptic('select'); setHeatVisible(next); }}
                onHeatLoaded={setHeatCells}
                onFocusPlace={focusMapOn}
              />

              <div className="eyebrow">过夜地点</div>
              {places.length === 0 ? (
                <p className="muted empty-hint">还没有足迹数据，开着 App 时会自动记录你的常去地点。</p>
              ) : (
                <div className="friend-list">
                  {places.map((p, i) => (
                    <button
                      className="friend-row"
                      type="button"
                      key={`${p.kind}-${p.lat}-${p.lng}-${i}`}
                      onClick={() => focusMapOn(p.lat, p.lng)}
                    >
                      <span
                        className="avatar"
                        style={{ background: '#25c9b7' }}
                      >
                        🌙
                      </span>
                      <div>
                        <b>{p.label}</b>
                        <small>{p.score} 晚</small>
                      </div>
                    </button>
                  ))}
                </div>
              )}

              <div className="privacy-note">
                <Ghost size={19} />
                <div><b>过夜地点仅你可见</b><small>晚数和位置只保存在你自己的账号下</small></div>
              </div>

              <button className="danger-button" type="button" onClick={preview ? () => setPreview(false) : signOut}>
                <LogOut size={17} /> {preview ? '退出预览' : '退出登录'}
              </button>
            </div>
          )}

          {panel === 'messages' && (
            <div className="friend-list">
              {friends.length === 0 && (
                <div className="empty-state">
                  <p className="muted empty-hint">添加朋友后即可开始聊天</p>
                  <button className="primary compact" type="button" onClick={() => setPanel('add')}>添加朋友</button>
                </div>
              )}
              {friends.map(f => {
                const thread = threads[f.id] || [];
                const last = thread[thread.length - 1];
                const count = unread[f.id] || 0;
                return (
                  <button className="friend-row" key={f.id} type="button" onClick={() => openChat(f.id)}>
                    <Avatar profile={f} showStatus />
                    <div>
                      <b>{f.display_name}</b>
                      <small className={count ? 'strong' : ''}>{last ? last.body : '开始聊天…'}</small>
                    </div>
                    <span className="friend-meta">
                      {count > 0 && <span className="badge">{count}</span>}
                      {last && <small>{ago(last.created_at)}</small>}
                    </span>
                  </button>
                );
              })}
            </div>
          )}

          {panel === 'settings' && (
            <div className="ghost-panel">
              <p>选择朋友在地图上看到你的位置精度。模糊和冻结都由服务端处理，朋友拿不到你的真实坐标。</p>
              {GHOST_MODES.map(m => (
                <button key={m.value} type="button" className={ghostMode === m.value ? 'selected' : ''} onClick={() => changeGhostMode(m.value)}>
                  <span>{m.icon}</span>
                  <div><b>{m.title}</b><small>{m.detail}</small></div>
                  <i />
                </button>
              ))}

              <div className="eyebrow">针对单个好友</div>
              {friends.length === 0 ? (
                <p className="muted empty-hint">有好友之后就能单独设置了。</p>
              ) : (
                <div className="per-friend-list">
                  {friends.map(f => (
                    <div className="per-friend-row" key={f.id}>
                      <Avatar profile={f} />
                      <div><b>{f.display_name}</b><small>@{f.username}</small></div>
                      <div className="chip-row tight">
                        <button
                          type="button"
                          className={!friendModes[f.id] ? 'chip selected' : 'chip'}
                          onClick={() => changeFriendMode(f.id, null)}
                        >默认</button>
                        {GHOST_MODES.map(m => (
                          <button
                            key={m.value}
                            type="button"
                            className={friendModes[f.id] === m.value ? 'chip selected' : 'chip'}
                            onClick={() => changeFriendMode(f.id, m.value)}
                          >{m.icon}</button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}

              <div className="eyebrow">账号</div>
              <div className="danger-zone">
                {deleteArmed ? (
                  <>
                    <p className="danger-copy">
                      删除后你的位置、好友、消息和打卡记录会立即永久消失，无法恢复。
                    </p>
                    <div className="chip-row">
                      <button className="chip" type="button" onClick={() => setDeleteArmed(false)} disabled={deleting}>
                        取消
                      </button>
                      <button className="danger-button solid" type="button" onClick={confirmDeleteAccount} disabled={deleting}>
                        {deleting ? '删除中…' : '确认永久删除'}
                      </button>
                    </div>
                  </>
                ) : (
                  <button className="danger-button" type="button" onClick={() => { haptic('warning'); setDeleteArmed(true); }}>
                    删除账号
                  </button>
                )}
              </div>
            </div>
          )}
        </aside>
      )}

      {selected && (
        <PersonCard
          person={selected}
          myLocation={location}
          onClose={() => setSelectedId(null)}
          onChat={() => { openChat(selected.id); setSelectedId(null); }}
          onWave={async () => {
            const result = await wave(selected.id);
            notify(result.error || `已向 ${selected.display_name} 挥手 👋`);
          }}
          onWhatsUp={async () => {
            const result = await whatsUp(selected.id);
            notify(result.error || `已问 ${selected.display_name} 在干什么 👀`);
          }}
          onShare={() => shareCard(selected)}
          onReact={(emoji) => reactTo(selected, emoji)}
          onToggleBest={() => toggleBestFriend(selected)}
          onSend={(text) => send(selected.id, text)}
          onError={notify}
        />
      )}

      {chatFriend && (
        <ChatPanel
          friend={chatFriend}
          messages={threads[chatFriend.id] || []}
          meId={profile.id}
          onClose={() => { closeChat(); refreshUnread(); }}
          onSend={(text) => send(chatFriend.id, text)}
        />
      )}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}

export default App;
