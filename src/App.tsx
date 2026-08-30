import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import {
  BatteryCharging, Bell, Camera, ChevronDown, Footprints, Ghost, Loader2, LocateFixed, MapPin,
  MessageCircle, Navigation, Search, Send, SmilePlus, Sparkles, Users, X,
} from 'lucide-react';
import { AddFriendPanel } from './components/AddFriendPanel';
import { Avatar } from './components/Avatar';
import { ChatPanel } from './components/ChatPanel';
import { CompleteProfileScreen } from './components/CompleteProfileScreen';
import { SHEET_OFFSET_PX } from './lib/constants';
import { isConfigured, supabase } from './lib/supabase';
import { loadFriendsBundle, sendFriendRequest } from './services/friends';
import { getMyLastLocation, upsertMyLocation } from './services/locations';
import { uploadProfileAvatar } from './services/profile';
import { completeProfile, searchProfiles } from './services/profiles';
import type { Friend, GhostMode, LiveLocation, Message, Panel, Profile } from './types';
import { useMessages } from './hooks/useMessages';
import { useRealtime } from './hooks/useRealtime';
import { useSignificantPlaces } from './hooks/useSignificantPlaces';

const WORLD_CENTER: [number, number] = [20, 0];
const WORLD_ZOOM = 2;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const modes: { value: GhostMode; title: string; detail: string; icon: string }[] = [
  { value: 'precise', title: '精确位置', detail: '实时显示你的准确位置', icon: '◎' },
  { value: 'blurred', title: '模糊位置', detail: '随机偏移约 0.2–1.2 km', icon: '◌' },
  { value: 'frozen', title: '冻结位置', detail: '停留在上一次的位置', icon: '❄' },
];

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

function AuthScreen() {
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
      </section>
    </main>
  );
}

function App() {
  const [sessionReady, setSessionReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileLoaded, setProfileLoaded] = useState(false);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [sentIds, setSentIds] = useState<Set<string>>(new Set());
  const [addResults, setAddResults] = useState<Profile[]>([]);
  const [location, setLocation] = useState<LiveLocation | null>(null);
  const [locationLabel, setLocationLabel] = useState<string | null>(null);
  const [panel, setPanel] = useState<Panel>('friends');
  const [selected, setSelected] = useState<Friend | null>(null);
  const [ghostMode, setGhostMode] = useState<GhostMode>('precise');
  const [toast, setToast] = useState('');
  const [search, setSearch] = useState('');
  const [avatarBusy, setAvatarBusy] = useState(false);
  const [locating, setLocating] = useState(false);
  const [mapTileError, setMapTileError] = useState<string | null>(null);
  const [quickDraft, setQuickDraft] = useState('');
  // Held in state, not a ref, so map init reliably fires on the render that mounts the node.
  const [mapNode, setMapNode] = useState<HTMLDivElement | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  const tileLayerRef = useRef<L.TileLayer | null>(null);
  const didAutoFocus = useRef(false);
  const locationRef = useRef<LiveLocation | null>(null);
  locationRef.current = location;
  const { places, recordFix } = useSignificantPlaces(profile?.id, signedIn && Boolean(profile));
  const { threads, chatWith, openChat, closeChat, send, wave, pushIncoming } = useMessages(profile?.id);

  const handleFriendLocation = useCallback((userId: string, row: Record<string, unknown> | null) => {
    if (!row) return;
    setFriends(prev => prev.map(f => (
      f.id === userId ? { ...f, location: row as unknown as LiveLocation } : f
    )));
  }, []);

  const handleIncomingMessage = useCallback((msg: Message) => {
    pushIncoming(msg);
  }, [pushIncoming]);

  // Feed own fixes into private significant-place history (overnight/home/work).
  useEffect(() => {
    if (!location || !profile) return;
    recordFix(location.lat, location.lng, location.updated_at).catch(() => undefined);
  }, [location, profile, recordFix]);

  const notify = useCallback((text: string) => {
    setToast(text);
    window.setTimeout(() => setToast(''), 3200);
  }, []);

  const reloadFriends = useCallback(async (userId: string) => {
    const bundle = await loadFriendsBundle(userId);
    setFriends(bundle.friends);
    setSentIds(bundle.sentIds);
  }, []);

  useRealtime({
    meId: profile?.id,
    onFriendsChange: () => {
      if (profile?.id) reloadFriends(profile.id).catch(() => undefined);
    },
    onFriendLocation: handleFriendLocation,
    onMessage: handleIncomingMessage,
  });

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSignedIn(Boolean(data.session)); setSessionReady(true); });
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      setSignedIn(Boolean(next));
      setSessionReady(true);
      if (!next) {
        setProfile(null);
        setProfileLoaded(false);
        setFriends([]);
        setLocation(null);
        setLocationLabel(null);
        didAutoFocus.current = false;
      }
    });
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
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
      }
      setProfileLoaded(true);
    })();
  }, [signedIn, reloadFriends]);

  useEffect(() => {
    if (!signedIn || !profile || !navigator.geolocation) return;
    const watch = navigator.geolocation.watchPosition(
      async (p) => {
        const next: LiveLocation = {
          user_id: profile.id,
          lat: p.coords.latitude,
          lng: p.coords.longitude,
          accuracy: p.coords.accuracy,
          speed: p.coords.speed,
          updated_at: new Date().toISOString(),
        };
        setLocation(next);
        setLocationLabel(null);
        if (isUserUuid(profile.id) && ghostMode !== 'frozen') {
          await upsertMyLocation(next).catch(() => undefined);
        }
      },
      () => undefined,
      { enableHighAccuracy: true, maximumAge: 8000, timeout: 20000 },
    );
    return () => navigator.geolocation.clearWatch(watch);
  }, [signedIn, profile, ghostMode]);

  const focusMapOn = useCallback((lat: number, lng: number, zoom = 16) => {
    if (!map.current) return;
    const z = map.current.getZoom() < 14 ? zoom : map.current.getZoom();
    const pt = map.current.project(L.latLng(lat, lng), z);
    pt.y += SHEET_OFFSET_PX;
    map.current.flyTo(map.current.unproject(pt, z), z, { animate: true, duration: 0.8 });
  }, []);

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
      const icon = L.divIcon({
        className: 'person-pin-shell',
        html: `<div class="person-pin ${mine ? 'mine' : ''}" style="--pin:${color}"><div class="pin-face">${face}</div><b>${safeHtml(p.status_emoji)}</b></div>`,
        iconSize: [70, 82],
        iconAnchor: [35, 76],
      });
      const marker = L.marker([l.lat, l.lng], { icon, zIndexOffset: mine ? 1000 : 0 }).addTo(layers.current!);
      if (!mine) marker.on('click', () => { const f = friends.find(x => x.id === p.id); if (f) setSelected(f); });
    });
    // Private significant places (overnight spots / home / work).
    const PLACE_STYLE: Record<string, { icon: string; color: string }> = {
      overnight: { icon: '🌙', color: '#25c9b7' },
      home: { icon: '🏠', color: '#ff6f61' },
      work: { icon: '💼', color: '#8b7cf6' },
    };
    places.forEach(p => {
      const style = PLACE_STYLE[p.kind] || PLACE_STYLE.overnight;
      const icon = L.divIcon({
        className: 'place-pin-shell',
        html: `<div class="place-pin" style="--place:${style.color}"><span>${style.icon}</span><b>${safeHtml(p.label)}</b></div>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      L.marker([p.lat, p.lng], { icon, interactive: false, zIndexOffset: -500 }).addTo(layers.current!);
    });
  }, [friends, location, profile, places, mapReady]);

  async function locateMe() {
    if (locating || !profile) return;
    setLocating(true);
    try {
      if (!navigator.geolocation) {
        notify('当前浏览器不支持定位');
        return;
      }
      const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 0,
        });
      });
      const next: LiveLocation = {
        user_id: profile.id,
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        accuracy: pos.coords.accuracy,
        speed: pos.coords.speed,
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
      if (error instanceof GeolocationPositionError && error.code === error.PERMISSION_DENIED) {
        notify('请在浏览器设置中允许 Pinpop 使用位置信息');
      } else {
        notify('暂时无法获取位置，请开启定位权限后重试');
      }
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

  const filtered = useMemo(
    () => friends.filter(f => `${f.display_name} ${f.username}`.toLowerCase().includes(search.toLowerCase())),
    [friends, search],
  );

  const friendIds = useMemo(() => new Set(friends.map(f => f.id)), [friends]);
  const chatFriend = useMemo(
    () => (chatWith ? friends.find(f => f.id === chatWith) ?? null : null),
    [chatWith, friends],
  );

  if (!sessionReady) {
    return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;
  }
  if (!signedIn) return <AuthScreen />;
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

  return (
    <main className="app-shell">
      <div ref={setMapNode} className="map" />
      {mapTileError && <div className="map-error-banner">{mapTileError}</div>}
      {!location && (
        <div className="map-hint">
          <p>开启浏览器定位后，你的位置会显示在地图上。</p>
          <button type="button" className="primary compact" onClick={locateMe} disabled={locating}>
            {locating ? '定位中…' : '开启定位'}
          </button>
        </div>
      )}
      {locationLabel && <div className="location-label">{locationLabel}</div>}

      <header className="topbar">
        <button className="profile-chip" type="button" onClick={() => setPanel('world')}>
          <Avatar profile={profile} />
          <div><b>{profile.display_name}</b><small>{profile.status_emoji} {profile.status_text}</small></div>
          <ChevronDown size={16} />
        </button>
        <div className="top-actions">
          <button className="circle-button" type="button" onClick={() => notify('现在没有新通知')}><Bell size={20} /></button>
          <button className={`circle-button ${ghostMode !== 'precise' ? 'active' : ''}`} type="button" onClick={() => setPanel('settings')}><Ghost size={21} /></button>
        </div>
      </header>

      <div className="map-tools">
        <button type="button" onClick={locateMe} disabled={locating} aria-label="定位到我">
          {locating ? <Loader2 size={21} className="spin" /> : <LocateFixed size={21} />}
        </button>
        <button type="button" onClick={() => setPanel('places')}><MapPin size={21} /></button>
      </div>

      <nav className="dock">
        <button className={panel === 'friends' ? 'active' : ''} type="button" onClick={() => setPanel('friends')}><Users /><span>朋友</span></button>
        <button className={panel === 'places' ? 'active' : ''} type="button" onClick={() => setPanel('places')}><Search /><span>探索</span></button>
        <button className="center-action" type="button" disabled onClick={() => notify('挥手功能正在开发中')}><span>👋</span></button>
        <button className={panel === 'world' ? 'active' : ''} type="button" onClick={() => setPanel('world')}><Footprints /><span>足迹</span></button>
        <button className={panel === 'messages' ? 'active' : ''} type="button" onClick={() => setPanel('messages')}><MessageCircle /><span>消息</span></button>
      </nav>

      {panel === 'add' && profile && (
        <AddFriendPanel
          me={profile}
          results={addResults}
          sentIds={sentIds}
          friendIds={friendIds}
          onClose={() => setPanel('friends')}
          onSearch={(q) => { searchProfiles(profile.id, q).then(setAddResults).catch(() => undefined); }}
          onSendRequest={async (id) => {
            await sendFriendRequest(profile.id, id);
            setSentIds(prev => new Set(prev).add(id));
            notify('好友请求已发送');
          }}
          onNotify={notify}
        />
      )}

      {panel && panel !== 'add' && (
        <aside className="sheet">
          <div className="grabber" />
          <div className="sheet-head">
            <div>
              <div className="eyebrow">
                {panel === 'friends' ? '你的圈子' : panel === 'places' ? '身边正在发生' : panel === 'world' ? '你的世界' : panel === 'messages' ? '保持联系' : '位置隐私'}
              </div>
              <h2>
                {panel === 'friends' ? `${friends.length} 位朋友` : panel === 'places' ? '探索地点' : panel === 'world' ? '我的资料' : panel === 'messages' ? '消息' : 'Ghost Mode'}
              </h2>
            </div>
            <button className="close-button" type="button" onClick={() => setPanel(null)}><X size={19} /></button>
          </div>

          {panel === 'friends' && (
            <>
              <div className="search"><Search size={18} /><input placeholder="搜索朋友" value={search} onChange={e => setSearch(e.target.value)} /></div>
              <div className="friend-list">
                {filtered.length === 0 && (
                  <div className="empty-state">
                    <p className="muted empty-hint">还没有朋友</p>
                    <button className="primary compact" type="button" onClick={() => setPanel('add')}>添加朋友</button>
                  </div>
                )}
                {filtered.map(f => (
                  <button className="friend-row" key={f.id} type="button" onClick={() => { setSelected(f); if (f.location) focusMapOn(f.location.lat, f.location.lng); }}>
                    <Avatar profile={f} showStatus />
                    <div><b>{f.display_name}</b><small>@{f.username} · {f.status_text}</small></div>
                    <div className="friend-meta">
                      <span>{ago(f.location?.updated_at)}</span>
                      <small>{f.is_charging && <BatteryCharging size={13} />} {f.battery_level != null ? `${f.battery_level}%` : ''}</small>
                    </div>
                  </button>
                ))}
              </div>
            </>
          )}

          {panel === 'places' && (
            <div className="feature-grid">
              <button type="button" disabled><span className="feature-icon coral"><MapPin /></span><b>附近地点</b><small>功能正在开发中</small></button>
              <button type="button" disabled><span className="feature-icon violet"><Navigation /></span><b>在这里打卡</b><small>功能正在开发中</small></button>
            </div>
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
                        style={{ background: p.kind === 'home' ? '#ff6f61' : p.kind === 'work' ? '#8b7cf6' : '#25c9b7' }}
                      >
                        {p.kind === 'home' ? '🏠' : p.kind === 'work' ? '💼' : '🌙'}
                      </span>
                      <div>
                        <b>{p.label}</b>
                        <small>{p.kind === 'work' ? `累计 ${Math.round(p.score / 60)} 小时` : `${p.score} 晚`}</small>
                      </div>
                    </button>
                  ))}
                </div>
              )}
              <button className="privacy-note" type="button" disabled>
                <Ghost size={19} />
                <div><b>足迹默认仅你可见</b><small>过夜地点 / Home / Work 仅保存在你自己的账号下</small></div>
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
                return (
                  <button className="friend-row" key={f.id} type="button" onClick={() => openChat(f.id)}>
                    <Avatar profile={f} showStatus />
                    <div>
                      <b>{f.display_name}</b>
                      <small>{last ? last.body : '开始聊天…'}</small>
                    </div>
                    {last && <span className="friend-meta">{ago(last.created_at)}</span>}
                  </button>
                );
              })}
            </div>
          )}

          {panel === 'settings' && (
            <div className="ghost-panel">
              <p>选择朋友在地图上看到你的位置精度。服务端隐私控制仍在开发中。</p>
              {modes.map(m => (
                <button key={m.value} type="button" className={ghostMode === m.value ? 'selected' : ''} onClick={() => { setGhostMode(m.value); notify(`已切换为${m.title}（仅本地 UI）`); }}>
                  <span>{m.icon}</span>
                  <div><b>{m.title}</b><small>{m.detail}</small></div>
                  <i />
                </button>
              ))}
              <div className="setting-row"><div><b>针对单个好友设置</b><small>功能正在开发中</small></div><span>即将开放</span></div>
            </div>
          )}
        </aside>
      )}

      {selected && (
        <section className="person-card">
          <button className="close-button" type="button" onClick={() => setSelected(null)}><X size={18} /></button>
          <Avatar profile={selected} className="big-avatar" showStatus />
          <h2>{selected.display_name}</h2>
          <p>@{selected.username} · {ago(selected.location?.updated_at)}</p>
          <div className="presence">
            <span className="pulse" />
            <b>{selected.status_text}</b>
            {selected.battery_level != null && <small>{selected.battery_level}% 电量</small>}
          </div>
          <div className="person-actions">
            <button type="button" onClick={async () => { await wave(selected.id); notify(`已向 ${selected.display_name} 挥手 👋`); }}><SmilePlus /><span>打招呼</span></button>
            <button type="button" onClick={() => notify('What\'s Up 功能正在开发中')}><Sparkles /><span>What&apos;s Up</span></button>
            <button type="button" onClick={() => { openChat(selected.id); setSelected(null); }}><MessageCircle /><span>聊天</span></button>
          </div>
          <div className="quick-message">
            <input
              placeholder={`给 ${selected.display_name} 发消息…`}
              value={quickDraft}
              onChange={e => setQuickDraft(e.target.value)}
              onKeyDown={async (e) => {
                if (e.key !== 'Enter' || !quickDraft.trim()) return;
                const result = await send(selected.id, quickDraft);
                if (result.error) notify(result.error);
                else { setQuickDraft(''); openChat(selected.id); setSelected(null); }
              }}
            />
            <button
              type="button"
              onClick={async () => {
                if (!quickDraft.trim()) return;
                const result = await send(selected.id, quickDraft);
                if (result.error) notify(result.error);
                else { setQuickDraft(''); openChat(selected.id); setSelected(null); }
              }}
            ><Send size={18} /></button>
          </div>
        </section>
      )}

      {chatFriend && profile && (
        <ChatPanel
          friend={chatFriend}
          messages={threads[chatFriend.id] || []}
          meId={profile.id}
          onClose={closeChat}
          onSend={(text) => send(chatFriend.id, text)}
        />
      )}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}

export default App;
