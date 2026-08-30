import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import {
  BatteryCharging, Bell, Camera, ChevronDown, Footprints, Ghost, LocateFixed, MapPin,
  MessageCircle, Navigation, Search, Send, SmilePlus, Sparkles, Users, X,
} from 'lucide-react';
import { Avatar } from './components/Avatar';
import { CompleteProfileScreen } from './components/CompleteProfileScreen';
import { demoFriends, demoLocation, demoMe } from './data/demo';
import { isConfigured, supabase } from './lib/supabase';
import { uploadProfileAvatar } from './services/profile';
import { completeProfile } from './services/profiles';
import type { Friend, GhostMode, LiveLocation, Panel, Profile } from './types';

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

function Auth({ onDemo }: { onDemo: () => void }) {
  const [signup, setSignup] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [username, setUsername] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!isConfigured) { setMessage('尚未配置 Supabase。可先进入预览模式。'); return; }
    if (signup && (!displayName.trim() || !username.trim())) { setMessage('请填写昵称和用户名。'); return; }
    setBusy(true); setMessage('');
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

  return <main className="auth-shell">
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
      {signup && <div className="name-fields"><label>昵称<input value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="Leo" /></label><label>用户名<input value={username} onChange={e => setUsername(e.target.value)} placeholder="leo_01" /></label></div>}
      <label>邮箱<input value={email} onChange={e => setEmail(e.target.value)} type="email" placeholder="you@example.com" /></label>
      <label>密码<input value={password} onChange={e => setPassword(e.target.value)} type="password" placeholder="至少 6 位" /></label>
      {message && <div className="form-message">{message}</div>}
      <button className="primary wide" disabled={busy} onClick={submit}>{busy ? '请稍候…' : signup ? '注册' : '登录'}</button>
      <button className="text-button" onClick={() => setSignup(!signup)}>{signup ? '已经有账号？登录' : '第一次来？创建账号'}</button>
      <div className="rule"><span>或者</span></div>
      <button className="preview-button" onClick={onDemo}><Sparkles size={17} /> 先看看新版长什么样</button>
    </section>
  </main>;
}

function App() {
  const [preview, setPreview] = useState(false);
  const [sessionReady, setSessionReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [profileLoaded, setProfileLoaded] = useState(false);
  const [friends, setFriends] = useState<Friend[]>([]);
  const [location, setLocation] = useState<LiveLocation>(demoLocation);
  const [panel, setPanel] = useState<Panel>('friends');
  const [selected, setSelected] = useState<Friend | null>(null);
  const [ghostMode, setGhostMode] = useState<GhostMode>('precise');
  const [toast, setToast] = useState('');
  const [search, setSearch] = useState('');
  const [avatarBusy, setAvatarBusy] = useState(false);
  const mapEl = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSignedIn(Boolean(data.session)); setSessionReady(true); });
    const { data } = supabase.auth.onAuthStateChange((_event, next) => { setSignedIn(Boolean(next)); setSessionReady(true); });
    return () => data.subscription.unsubscribe();
  }, []);

  const me = preview || !profile ? demoMe : profile;

  useEffect(() => {
    if (!signedIn || preview) {
      setProfile(null);
      setProfileLoaded(!signedIn || preview);
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
      const { data: rels } = await supabase.from('friendships').select('*').eq('status', 'accepted').or(`requester_id.eq.${user.user.id},addressee_id.eq.${user.user.id}`);
      const ids = (rels || []).map(r => r.requester_id === user.user!.id ? r.addressee_id : r.requester_id);
      if (ids.length) {
        const [{ data: profiles }, { data: locations }] = await Promise.all([
          supabase.from('profiles').select('*').in('id', ids), supabase.from('locations').select('*').in('user_id', ids),
        ]);
        setFriends((profiles || []).map(p => ({ ...p, location: (locations || []).find(l => l.user_id === p.id) })) as Friend[]);
      } else setFriends([]);
      setProfileLoaded(true);
    })();
  }, [signedIn, preview]);

  useEffect(() => {
    if ((!signedIn && !preview) || !navigator.geolocation || preview || !profile) return;
    const watch = navigator.geolocation.watchPosition(async p => {
      const next = { user_id: profile.id, lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy, speed: p.coords.speed, updated_at: new Date().toISOString() };
      setLocation(next);
      if (signedIn && ghostMode !== 'frozen') await supabase.from('locations').upsert(next, { onConflict: 'user_id' });
    }, () => undefined, { enableHighAccuracy: true, maximumAge: 15000, timeout: 20000 });
    return () => navigator.geolocation.clearWatch(watch);
  }, [signedIn, preview, profile, ghostMode]);

  useEffect(() => {
    if ((!signedIn && !preview) || !mapEl.current || map.current) return;
    map.current = L.map(mapEl.current, { zoomControl: false, attributionControl: false }).setView([location.lat, location.lng], 14);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(map.current);
    layers.current = L.layerGroup().addTo(map.current);
    setTimeout(() => map.current?.invalidateSize(), 50);
    return () => { map.current?.remove(); map.current = null; };
  }, [signedIn, preview]);

  useEffect(() => {
    if (!layers.current) return;
    layers.current.clearLayers();
    const people: { p: Profile | Friend; l?: LiveLocation | null; mine?: boolean }[] = [{ p: me, l: location, mine: true }, ...friends.map(p => ({ p, l: p.location }))];
    people.forEach(({ p, l, mine }) => {
      if (!l) return;
      const color = /^#[0-9a-f]{6}$/i.test(p.avatar_color) ? p.avatar_color : '#ff6658';
      const face = p.avatar_url
        ? `<img src="${safeHtml(p.avatar_url)}" alt="" referrerpolicy="no-referrer">`
        : `<span>${safeHtml(initials(p.display_name))}</span>`;
      const icon = L.divIcon({ className: 'person-pin-shell', html: `<div class="person-pin ${mine ? 'mine' : ''}" style="--pin:${color}"><div class="pin-face">${face}</div><b>${safeHtml(p.status_emoji)}</b></div>`, iconSize: [70, 82], iconAnchor: [35, 76] });
      const marker = L.marker([l.lat, l.lng], { icon }).addTo(layers.current!);
      if (!mine) marker.on('click', () => { const f = friends.find(x => x.id === p.id); if (f) setSelected(f); });
    });
  }, [friends, location, me]);

  const filtered = useMemo(() => friends.filter(f => `${f.display_name} ${f.username}`.toLowerCase().includes(search.toLowerCase())), [friends, search]);
  function notify(text: string) { setToast(text); window.setTimeout(() => setToast(''), 2600); }
  function focus(lat?: number, lng?: number) { if (lat != null && lng != null) map.current?.flyTo([lat, lng], 16, { duration: .7 }); }
  async function changeAvatar(file?: File) {
    if (!file) return;
    setAvatarBusy(true);
    try {
      if (preview) {
        setProfile(current => current ? { ...current, avatar_url: URL.createObjectURL(file) } : current);
      } else if (profile) {
        const avatarUrl = await uploadProfileAvatar(profile.id, file);
        setProfile(current => current ? { ...current, avatar_url: avatarUrl } : current);
      }
      notify('新头像已经换好啦 ✨');
    } catch (error) {
      notify(error instanceof Error ? error.message : '头像上传失败，请稍后再试');
    } finally {
      setAvatarBusy(false);
    }
  }

  if (!sessionReady) return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;
  if (!signedIn && !preview) return <Auth onDemo={() => { setFriends(demoFriends); setPreview(true); }} />;
  if (signedIn && profileLoaded && !profile && !preview) {
    return <CompleteProfileScreen onComplete={async (username, displayName) => {
      const { data: user } = await supabase.auth.getUser();
      if (!user.user) return { error: '登录状态已失效，请重新登录' };
      const result = await completeProfile(user.user.id, username, displayName);
      if (result.error) return { error: result.error };
      if (result.profile) setProfile(result.profile);
      return {};
    }} />;
  }
  if (signedIn && !profileLoaded) return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;

  return <main className="app-shell">
    <div ref={mapEl} className="map" />
    <header className="topbar">
      <button className="profile-chip" onClick={() => setPanel('world')}><Avatar profile={me} /><div><b>{me.display_name}</b><small>{me.status_emoji} {me.status_text}</small></div><ChevronDown size={16} /></button>
      <div className="top-actions">
        {preview && <button className="demo-badge" onClick={() => { setPreview(false); setFriends([]); }}>预览模式 · 返回登录</button>}
        <button className="circle-button" onClick={() => notify('现在没有新通知')}><Bell size={20} /></button>
        <button className={`circle-button ${ghostMode !== 'precise' ? 'active' : ''}`} onClick={() => setPanel('settings')}><Ghost size={21} /></button>
      </div>
    </header>

    <div className="map-tools">
      <button onClick={() => focus(location.lat, location.lng)}><LocateFixed size={21} /></button>
      <button onClick={() => setPanel('places')}><MapPin size={21} /></button>
    </div>

    <div className="map-mood"><span>☀️ 24°</span><b>Santa Monica</b><small>{friends.length} 位朋友在附近</small></div>

    <nav className="dock">
      <button className={panel === 'friends' ? 'active' : ''} onClick={() => setPanel('friends')}><Users /><span>朋友</span></button>
      <button className={panel === 'places' ? 'active' : ''} onClick={() => setPanel('places')}><Search /><span>探索</span></button>
      <button className="center-action" onClick={() => notify('已向所有在线好友发送 👋')}><span>👋</span></button>
      <button className={panel === 'world' ? 'active' : ''} onClick={() => setPanel('world')}><Footprints /><span>足迹</span></button>
      <button className={panel === 'messages' ? 'active' : ''} onClick={() => setPanel('messages')}><MessageCircle /><span>消息</span></button>
    </nav>

    {panel && <aside className="sheet">
      <div className="grabber" />
      <div className="sheet-head">
        <div><div className="eyebrow">{panel === 'friends' ? '你的圈子' : panel === 'places' ? '身边正在发生' : panel === 'world' ? '你的世界' : panel === 'messages' ? '保持联系' : '位置隐私'}</div><h2>{panel === 'friends' ? `${friends.length} 位朋友` : panel === 'places' ? '探索地点' : panel === 'world' ? '本周足迹' : panel === 'messages' ? '消息' : 'Ghost Mode'}</h2></div>
        <button className="close-button" onClick={() => setPanel(null)}><X size={19} /></button>
      </div>

      {panel === 'friends' && <>
        <div className="search"><Search size={18} /><input placeholder="搜索朋友" value={search} onChange={e => setSearch(e.target.value)} /></div>
        <div className="friend-list">{filtered.map(f => <button className="friend-row" key={f.id} onClick={() => { setSelected(f); focus(f.location?.lat, f.location?.lng); }}>
          <Avatar profile={f} showStatus />
          <div><b>{f.display_name}</b><small>@{f.username} · {f.status_text}</small></div>
          <div className="friend-meta"><span>{ago(f.location?.updated_at)}</span><small>{f.is_charging && <BatteryCharging size={13} />} {f.battery_level ?? '—'}%</small></div>
        </button>)}</div>
      </>}

      {panel === 'places' && <div className="feature-grid">
        <button onClick={() => notify('地点搜索将在连接 Places API 后启用')}><span className="feature-icon coral"><MapPin /></span><b>附近地点</b><small>餐厅、咖啡店与朋友常去的地方</small></button>
        <button onClick={() => notify('已记录当前地点')}><span className="feature-icon violet"><Navigation /></span><b>在这里打卡</b><small>把此刻加入你的私人地图</small></button>
        <div className="place-card"><div className="place-visual">☕️</div><div><b>Santa Monica</b><small>你和 2 位朋友最近来过</small></div></div>
      </div>}

      {panel === 'world' && <div className="world-panel">
        <div className="profile-spotlight"><div className="avatar-editor"><Avatar profile={me} className="profile-avatar" showStatus /><label className={avatarBusy ? 'uploading' : ''}><Camera size={16}/><span>{avatarBusy ? '上传中…' : '换头像'}</span><input type="file" accept="image/jpeg,image/png,image/webp" disabled={avatarBusy} onChange={e => changeAvatar(e.target.files?.[0])}/></label></div><div><span>@{me.username}</span><strong>{me.display_name}</strong><small>让朋友一眼就在地图上找到你</small></div></div>
        <div className="stat-card hero-stat"><span>本周探索</span><strong>23.8<small> km</small></strong><div className="mini-bars"><i/><i/><i/><i/><i/><i/><i/></div></div>
        <div className="stat-row"><div className="stat-card"><span>到访地点</span><strong>12</strong><small>3 个新地点</small></div><div className="stat-card"><span>相聚时间</span><strong>8.4h</strong><small>和 Maya 最久</small></div></div>
        <button className="privacy-note"><Ghost size={19}/><div><b>足迹默认仅你可见</b><small>你可以随时删除地点历史</small></div></button>
      </div>}

      {panel === 'messages' && <div className="friend-list">{friends.map(f => <button className="friend-row" key={f.id} onClick={() => setSelected(f)}><Avatar profile={f} /><div><b>{f.display_name}</b><small>{f.id === 'maya' ? '晚点海边见！' : `${f.status_emoji} ${f.status_text}`}</small></div><span className="unread">{f.id === 'maya' ? '2' : ''}</span></button>)}</div>}

      {panel === 'settings' && <div className="ghost-panel">
        <p>选择朋友在地图上看到你的位置精度。你可以随时切换。</p>
        {modes.map(m => <button key={m.value} className={ghostMode === m.value ? 'selected' : ''} onClick={() => { setGhostMode(m.value); notify(`已切换为${m.title}`); }}><span>{m.icon}</span><div><b>{m.title}</b><small>{m.detail}</small></div><i /></button>)}
        <div className="setting-row"><div><b>针对单个好友设置</b><small>为不同朋友选择不同模式</small></div><span>即将开放</span></div>
      </div>}
    </aside>}

    {selected && <section className="person-card">
      <button className="close-button" onClick={() => setSelected(null)}><X size={18}/></button>
      <Avatar profile={selected} className="big-avatar" showStatus />
      <h2>{selected.display_name}</h2><p>@{selected.username} · {ago(selected.location?.updated_at)}</p>
      <div className="presence"><span className="pulse"/><b>{selected.status_text}</b><small>{selected.battery_level}% 电量</small></div>
      <div className="person-actions"><button onClick={() => notify(`已向 ${selected.display_name} 发送 👋`)}><SmilePlus/><span>打招呼</span></button><button onClick={() => notify('What’s Up 请求已发送')}><Sparkles/><span>What's Up</span></button><button onClick={() => setPanel('messages')}><MessageCircle/><span>聊天</span></button></div>
      <div className="quick-message"><input placeholder={`给 ${selected.display_name} 发消息…`} /><button onClick={() => notify('消息已发送')}><Send size={18}/></button></div>
    </section>}

    {toast && <div className="toast">{toast}</div>}
  </main>;
}

export default App;
