import { useCallback, useEffect, useMemo, useState } from 'react';
import { LocateFixed, MapPin, X } from 'lucide-react';
import { demoFriends, demoLocation, demoMe } from './data/demo';
import { AuthScreen } from './components/AuthScreen';
import { CompleteProfileScreen } from './components/CompleteProfileScreen';
import { MapCanvas } from './components/MapCanvas';
import { TopBar } from './components/TopBar';
import { BottomDock } from './components/BottomDock';
import { FriendsPanel } from './components/FriendsPanel';
import { PersonCard, MeCard } from './components/PersonCard';
import { AddFriendPanel } from './components/AddFriendPanel';
import { ChatPanel } from './components/ChatPanel';
import { GhostModePanel } from './components/GhostModePanel';
import { useAuth } from './hooks/useAuth';
import { useFriends } from './hooks/useFriends';
import { useGeolocation } from './hooks/useGeolocation';
import { useMessages } from './hooks/useMessages';
import { useRealtime } from './hooks/useRealtime';
import { getGhostMode, nextStatus, setGhostMode, updateStatus } from './services/profiles';
import { inviteText, shareText } from './lib/geo';
import type { Friend, GhostMode, LiveLocation, Panel } from './types';

function panelTitle(panel: Panel) {
  if (panel === 'friends') return '你的圈子';
  if (panel === 'places') return '探索地点';
  if (panel === 'world') return '本周足迹';
  if (panel === 'messages') return '保持联系';
  if (panel === 'settings') return 'Ghost Mode';
  return '';
}

export default function App() {
  const auth = useAuth();
  const [preview, setPreview] = useState(false);
  const [panel, setPanel] = useState<Panel>('friends');
  const [selected, setSelected] = useState<Friend | null>(null);
  const [showMe, setShowMe] = useState(false);
  const [ghostMode, setGhostModeState] = useState<GhostMode>('precise');
  const [toast, setToast] = useState('');
  const [search, setSearch] = useState('');
  const [focus, setFocus] = useState<{ lat: number; lng: number } | null>(null);
  const [inviteQuery, setInviteQuery] = useState('');

  const me = preview || !auth.profile ? demoMe : auth.profile;
  const meId = preview ? undefined : auth.profile?.id;
  const friendsApi = useFriends(meId);
  const friends = preview ? demoFriends : friendsApi.friends;
  const { location, setLocation } = useGeolocation(meId, !preview && auth.signedIn, ghostMode);
  const myLocation = preview ? demoLocation : location;
  const messagesApi = useMessages(meId);

  const notify = useCallback((text: string) => {
    setToast(text);
    window.setTimeout(() => setToast(''), 2600);
  }, []);

  const reloadFriends = useCallback(() => { friendsApi.reload().catch(() => undefined); }, [friendsApi]);

  useEffect(() => {
    if (meId && auth.signedIn) {
      reloadFriends();
      getGhostMode(meId).then(setGhostModeState).catch(() => undefined);
    }
  }, [meId, auth.signedIn, reloadFriends]);

  useRealtime({
    meId,
    onFriendsChange: reloadFriends,
    onFriendLocation: (userId, row) => {
      if (!row) return;
      friendsApi.patchFriendLocation(userId, row as unknown as LiveLocation);
    },
    onMessage: (msg) => {
      if (!meId) return;
      if (msg.recipient_id === meId) {
        messagesApi.pushIncoming(msg);
        if (messagesApi.chatWith !== msg.sender_id) {
          const name = friends.find((f) => f.id === msg.sender_id)?.display_name || '好友';
          notify(`${name}：${msg.body}`);
        }
      } else if (msg.sender_id === meId && messagesApi.chatWith === msg.recipient_id) {
        messagesApi.reloadThread(msg.recipient_id).catch(() => undefined);
      }
    },
  });

  useEffect(() => {
    if (!auth.signedIn || preview) return;
    const add = new URLSearchParams(window.location.search).get('add');
    if (!add || !auth.profile) return;
    const username = add.replace(/^@/, '').trim().toLowerCase();
    if (!username || username === auth.profile.username) return;
    setPanel('add');
    setInviteQuery(username);
    notify('朋友分享来的邀请，点「＋ 添加」加好友');
    window.history.replaceState({}, '', window.location.pathname);
  }, [auth.signedIn, auth.profile, preview, notify]);

  const focusPerson = useCallback((lat?: number, lng?: number) => {
    if (lat != null && lng != null) setFocus({ lat, lng });
  }, []);

  const focusOnMe = useCallback(() => {
    if (!myLocation) return notify('正在获取你的位置…请允许定位权限');
    focusPerson(myLocation.lat, myLocation.lng);
  }, [myLocation, focusPerson, notify]);

  async function changeGhostMode(mode: GhostMode) {
    setGhostModeState(mode);
    if (!meId || preview) return;
    await setGhostMode(meId, mode, myLocation ? { lat: myLocation.lat, lng: myLocation.lng } : undefined);
  }

  async function cycleStatus() {
    if (!auth.profile || preview) return;
    const next = nextStatus(auth.profile.status_emoji);
    auth.setProfile({ ...auth.profile, status_emoji: next.emoji, status_text: next.text });
    await updateStatus(auth.profile.id, next.emoji, next.text);
  }

  async function shareSelf() {
    if (!auth.profile) return;
    const text = inviteText(auth.profile.username, auth.profile.display_name);
    const result = await shareText('Pinpop 好友邀请', text, text.split('\n').pop() || '');
    notify(result === 'shared' ? '已分享你的邀请' : '邀请链接已复制，发给朋友吧！');
  }

  const friendIds = useMemo(() => new Set(friends.map((f) => f.id)), [friends]);
  const chatFriend = friends.find((f) => f.id === messagesApi.chatWith) || null;

  if (!auth.ready) {
    return <div className="splash"><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>;
  }

  if (!preview && auth.session && auth.needsProfile) {
    return <CompleteProfileScreen onComplete={(username, displayName) => auth.finishProfile(auth.session!.user.id, username, displayName)} />;
  }

  if (!auth.signedIn && !preview) {
    return <AuthScreen onLogin={auth.login} onRegister={auth.register} onPreview={() => setPreview(true)} />;
  }

  return (
    <main className="app-shell">
      <MapCanvas
        me={me}
        friends={friends}
        myLocation={myLocation}
        focus={focus}
        onSelectMe={() => { setShowMe(true); setSelected(null); focusOnMe(); }}
        onSelectFriend={(f) => { setSelected(f); setShowMe(false); focusPerson(f.location?.lat, f.location?.lng); }}
      />

      <TopBar
        me={me}
        preview={preview}
        ghostMode={ghostMode}
        onOpenWorld={() => setPanel('world')}
        onOpenSettings={() => setPanel('settings')}
        onExitPreview={() => setPreview(false)}
        onNotify={notify}
      />

      <div className="map-tools">
        <button type="button" onClick={focusOnMe}><LocateFixed size={21} /></button>
        <button type="button" onClick={() => setPanel('places')}><MapPin size={21} /></button>
        <button type="button" className="add-fab" onClick={() => setPanel('add')}>＋</button>
      </div>

      <BottomDock panel={panel} onChange={setPanel} onWaveAll={() => notify('已向所有在线好友发送 👋')} />

      {panel && panel !== 'add' && (
        <aside className="sheet">
          <div className="grabber" />
          <div className="sheet-head">
            <div><div className="eyebrow">{panelTitle(panel)}</div><h2>{panel === 'friends' ? `${friends.length} 位朋友` : panelTitle(panel)}</h2></div>
            <button className="close-button" type="button" onClick={() => setPanel(null)}><X size={19} /></button>
          </div>

          {panel === 'friends' && (
            <FriendsPanel
              friends={friends}
              requests={friendsApi.requests}
              myLocation={myLocation}
              search={search}
              onSearch={setSearch}
              onSelectFriend={(f) => { setSelected(f); focusPerson(f.location?.lat, f.location?.lng); }}
              onRespond={(relId, status) => friendsApi.respond(relId, status).catch((e) => notify(String(e)))}
            />
          )}

          {panel === 'places' && (
            <div className="feature-grid">
              <button type="button" onClick={() => notify('地点搜索将在连接 Places API 后启用')}><span className="feature-icon coral"><MapPin /></span><b>附近地点</b><small>餐厅、咖啡店与朋友常去的地方</small></button>
              <div className="place-card"><div className="place-visual">☕️</div><div><b>打卡</b><small>把此刻加入你的私人地图</small></div></div>
            </div>
          )}

          {panel === 'world' && (
            <div className="world-panel">
              <div className="stat-card hero-stat"><span>本周探索</span><strong>—<small> km</small></strong></div>
              <div className="privacy-note"><span>足迹默认仅你可见</span></div>
            </div>
          )}

          {panel === 'messages' && (
            <div className="friend-list">
              {friends.map((f) => (
                <button className="friend-row" type="button" key={f.id} onClick={() => messagesApi.openChat(f.id)}>
                  <span className="avatar" style={{ background: f.avatar_color }}>{f.display_name.slice(0, 1)}</span>
                  <div><b>{f.display_name}</b><small>{f.status_emoji} {f.status_text}</small></div>
                </button>
              ))}
            </div>
          )}

          {panel === 'settings' && <GhostModePanel mode={ghostMode} onChange={changeGhostMode} onNotify={notify} />}
        </aside>
      )}

      {panel === 'add' && !preview && auth.profile && (
        <AddFriendPanel
          me={auth.profile}
          results={friendsApi.searchResults}
          sentIds={friendsApi.sentIds}
          friendIds={friendIds}
          initialQuery={inviteQuery}
          onClose={() => setPanel('friends')}
          onSearch={(q) => friendsApi.search(q).catch(() => undefined)}
          onSendRequest={friendsApi.sendRequest}
          onNotify={notify}
        />
      )}

      {selected && <PersonCard person={selected} onClose={() => setSelected(null)} onChat={() => messagesApi.openChat(selected.id)} onWave={() => messagesApi.wave(selected.id).then(() => notify(`已向 ${selected.display_name} 打招呼`))} onNotify={notify} />}
      {showMe && auth.profile && !preview && <MeCard me={auth.profile} onClose={() => setShowMe(false)} onAddFriend={() => setPanel('add')} onCycleStatus={cycleStatus} onShareSelf={shareSelf} onLogout={() => auth.logout().then(() => window.location.reload())} />}

      {chatFriend && <ChatPanel friend={chatFriend} messages={messagesApi.threads[chatFriend.id] || []} meId={meId!} onClose={messagesApi.closeChat} onSend={(text) => messagesApi.send(chatFriend.id, text)} />}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}
