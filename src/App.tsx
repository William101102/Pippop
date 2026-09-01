import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import {
  BatteryCharging, Bell, Camera, ChevronDown, ExternalLink, Ghost, Loader2, LocateFixed,
  LogOut, MapPin, MessageCircle, Moon, Search, Share2, ShieldCheck, Sparkles, Star, Sun, SunMoon,
  User, Users, X,
} from 'lucide-react';
import { AddFriendPanel } from './components/AddFriendPanel';
import { Avatar } from './components/Avatar';
import { ChatPanel } from './components/ChatPanel';
import { CheckInPanel } from './components/CheckInPanel';
import { CompleteProfileScreen } from './components/CompleteProfileScreen';
import { FootprintsPanel } from './components/FootprintsPanel';
import { FriendRail } from './components/FriendRail';
import { HighlightsRail } from './components/HighlightsRail';
import { HighlightViewer } from './components/HighlightViewer';
import { GiftToast } from './components/GiftToast';
import { GroupChatPanel } from './components/GroupChatPanel';
import { InviteWelcomeCard } from './components/InviteWelcomeCard';
import { NearbyPanel } from './components/NearbyPanel';
import { NewGroupSheet } from './components/NewGroupSheet';
import { PostHighlightSheet } from './components/PostHighlightSheet';
import { ZonesSection } from './components/ZonesSection';
import { NotificationsPanel, type UnreadPreview } from './components/NotificationsPanel';
import { PersonCard } from './components/PersonCard';
import { RequestsInbox } from './components/RequestsInbox';
import { StatusEditor } from './components/StatusEditor';
import { GHOST_MODES, PRIVACY_POLICY_URL, SHEET_OFFSET_PX } from './lib/constants';
import { fmtDist, fmtSpeed } from './lib/format';
import { streakInfo } from './lib/streak';
import { clusterByPixels } from './lib/cluster';
import {
  friendShareText, haversineKm, inviteText, inviteTokenFromUrl, inviteUrl, shareText, usernameFromInviteUrl,
} from './lib/geo';
import { createGeofenceTracker, createZoneGeofenceTracker } from './lib/geofence';
import { createFixGate, getCurrentFix, watchLocation } from './lib/location';
import { dismissSplash, getLaunchUrl, haptic, isNative, onAppResume, onAppUrlOpen, openAppSettings } from './lib/native';
import { clearPushBadge, registerPush, unregisterPush } from './lib/push';
import { isConfigured, supabase } from './lib/supabase';
import {
  THEME_CYCLE, THEME_LABEL, applyTheme, readThemePreference, storeThemePreference,
  watchSystemTheme, type ThemePreference,
} from './lib/theme';
import { publishWidgetSnapshot } from './lib/widget';
import { checkIn, loadMyVisits, loadNearbyPlaces } from './services/checkins';
import {
  loadMyReactions, loadPlaceEvents, recordPlaceEvent, sendReaction, setBestFriend, THROWABLES,
} from './services/social';
import {
  createInviteToken, fetchFriendLocation, loadFriendsBundle, redeemInvite, respondFriendRequest, sendFriendRequest,
} from './services/friends';
import {
  deleteHighlight, loadFriendHighlights, postHighlight, uploadHighlightPhoto,
} from './services/highlights';
import { createGroup, loadGroupThread, loadMyGroups, sendGroupMessage } from './services/groups';
import { getMyLastLocation, upsertMyLocation } from './services/locations';
import { createZone, deleteZone, loadVisibleZones } from './services/zones';
import { uploadProfileAvatar } from './services/profile';
import {
  completeProfile, deleteMyAccount, getFriendGhostModes, getGhostMode, searchProfiles,
  setFriendGhostMode, setGhostMode as persistGhostMode, updateStatus,
} from './services/profiles';
import type {
  ChatGroup, Friend, FriendRequest, GhostMode, HeatCell, Highlight, LiveLocation, MapReaction, Message,
  NearbyPlace, Panel, PlaceCategory, PlaceEvent, Profile, Visit, VisitVisibility, Zone,
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
  if (!iso) return 'No location';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  return `${Math.floor(mins / 60)}h ago`;
}

function initials(name: string) { return name.trim().slice(0, 1).toUpperCase(); }
function safeHtml(value: string) {
  return value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]!);
}
function pinAvatarSrc(url: string, version: number) {
  const join = url.includes('?') ? '&' : '?';
  return `${url}${join}pin=${version}`;
}
function cssBackgroundUrl(url: string) {
  return url.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}
function pinFaceHtml(avatarUrl: string | null | undefined, displayName: string, version: number) {
  if (avatarUrl?.trim()) {
    const src = cssBackgroundUrl(pinAvatarSrc(avatarUrl, version));
    return `<span class="pin-face-fill"><span class="pin-photo" style="background-image:url('${src}')"></span></span>`;
  }
  return `<span class="pin-face-fill"><span>${safeHtml(initials(displayName))}</span></span>`;
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

/** Apple's logo is a trademark — render it inline as a small monochrome mark
 *  rather than shipping an icon-font just for one glyph. */
function AppleMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 384 512" fill="currentColor" aria-hidden="true">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zM255.5 87.9c24.4-28.9 22.2-55.2 21.5-64.7-21.6 1.3-46.6 14.7-60.6 31.2-15.4 17.6-24.4 39.4-22.5 63.8 23.4 1.8 44.8-10.2 61.6-30.3z" />
    </svg>
  );
}

function AuthScreen({ onPreview }: { onPreview: () => void }) {
  const [appleBusy, setAppleBusy] = useState(false);
  const [signup, setSignup] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [username, setUsername] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (!isConfigured) { setMessage('Supabase isn\'t configured yet — contact an admin.'); return; }
    if (signup && (!displayName.trim() || !username.trim())) { setMessage('Please fill in a display name and username.'); return; }
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
    else if (signup && !result.data.session) setMessage('Signed up! Please check your email to confirm.');
  }

  return (
    <main className="auth-shell">
      <section className="auth-copy">
        <div className="auth-brand"><img src="./icons/icon-192.png" alt="" /><div className="brand brand-large"><span>pin</span>pop<i>●</i></div></div>
        <div className="auth-hero-copy"><span className="hero-kicker">YOUR PEOPLE, RIGHT NOW</span><h1>The map isn't just roads.<br />It's your world.</h1><p>See where friends are and what they're up to, then go meet up.</p></div>
        <div className="floating-face face-one">🛹</div><div className="floating-face face-two">☕️</div><div className="floating-face face-three">🎧</div>
      </section>
      <section className="auth-card">
        <img className="mobile-auth-logo" src="./icons/icon-192.png" alt="Pinpop" />
        <div className="eyebrow">WELCOME TO PINPOP</div>
        <h2>{signup ? 'Create your world' : 'Good to see you again'}</h2>
        <p className="muted">{signup ? 'Sign up, add friends, and light up the map together.' : 'Log in to see where your friends are.'}</p>
        {signup && (
          <div className="name-fields">
            <label>Display name<input value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="Your display name" /></label>
            <label>Username<input value={username} onChange={e => setUsername(e.target.value)} placeholder="your_id" /></label>
          </div>
        )}
        <label>Email<input value={email} onChange={e => setEmail(e.target.value)} type="email" placeholder="you@example.com" /></label>
        <label>Password<input value={password} onChange={e => setPassword(e.target.value)} type="password" placeholder="At least 6 characters" /></label>
        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" disabled={busy} onClick={submit}>{busy ? 'Please wait…' : signup ? 'Sign up' : 'Log in'}</button>
        <button
          className="apple-button wide"
          type="button"
          disabled={appleBusy || busy}
          onClick={async () => {
            if (!isConfigured) { setMessage('Supabase isn\'t configured yet — contact an admin.'); return; }
            setAppleBusy(true);
            setMessage('');
            // `scopes` is what actually asks Apple for the name/email; Apple
            // only ever returns them on the first grant.
            //
            // No `skipBrowserRedirect`: setting it stops supabase-js from
            // navigating and hands back `data.url` for the caller to open. If
            // nobody opens that URL the button silently does nothing and the
            // busy flag never clears — so either drive the redirect yourself or
            // let supabase-js do it. We let it do it.
            const { error } = await supabase.auth.signInWithOAuth({
              provider: 'apple',
              options: {
                scopes: 'name email',
                // Without this, Supabase falls back to the project's Site URL,
                // which drops users on the wrong page whenever the app is
                // served from a sub-path (GitHub Pages serves /zenly-app/).
                redirectTo: `${window.location.origin}${window.location.pathname}`,
                queryParams: { response_mode: 'form_post' },
              },
            });
            if (error) {
              setAppleBusy(false);
              setMessage(error.message);
            }
            // On success supabase-js navigates away; the redirect back reloads
            // the app and onAuthStateChange picks the session up.
          }}
        >
          {appleBusy ? 'Please wait…' : <><AppleMark /> Continue with Apple</>}
        </button>
        <button className="text-button" type="button" onClick={() => setSignup(!signup)}>{signup ? 'Already have an account? Log in' : 'First time here? Create an account'}</button>
        <div className="rule"><span>or</span></div>
        <button className="preview-button" type="button" onClick={onPreview}><Sparkles size={17} /> See what the app looks like first</button>
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
  const [pendingInviteToken, setPendingInviteToken] = useState('');
  const [inviteRedeeming, setInviteRedeeming] = useState(false);
  const [myInviteToken, setMyInviteToken] = useState<string | null>(null);
  const [newFriendWelcome, setNewFriendWelcome] = useState<Profile | null>(null);
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
  const [pinAvatarVersion, setPinAvatarVersion] = useState(0);
  const [locating, setLocating] = useState(false);
  const [waving, setWaving] = useState(false);
  const [mapTileError, setMapTileError] = useState<string | null>(null);
  const [locationDenied, setLocationDenied] = useState(false);
  const [deleteArmed, setDeleteArmed] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [heatVisible, setHeatVisible] = useState(false);
  // Day / night / auto. The preference is remembered; `applyTheme` writes the
  // resolved value to <html data-theme>, which is what the CSS matches on.
  const [themePref, setThemePref] = useState<ThemePreference>(() => readThemePreference());
  const [heatCells, setHeatCells] = useState<HeatCell[]>([]);
  const [myReactions, setMyReactions] = useState<MapReaction[]>([]);
  const [placeEvents, setPlaceEvents] = useState<PlaceEvent[]>([]);
  const [highlights, setHighlights] = useState<Record<string, Highlight[]>>({});
  const [highlightViewerId, setHighlightViewerId] = useState<string | null>(null);
  const [postingHighlight, setPostingHighlight] = useState(false);
  const [highlightBusy, setHighlightBusy] = useState(false);
  const [zones, setZones] = useState<Zone[]>([]);
  const [groups, setGroups] = useState<ChatGroup[]>([]);
  const [groupThreads, setGroupThreads] = useState<Record<string, Message[]>>({});
  const [openGroupId, setOpenGroupId] = useState<string | null>(null);
  const [creatingGroup, setCreatingGroup] = useState(false);
  const [incomingGift, setIncomingGift] = useState<{ sender: Profile; emoji: string; label?: string; key: number } | null>(null);
  const isBottomSheet = useBottomSheetLayout();
  // Held in state, not a ref, so map init reliably fires on the render that mounts the node.
  const [mapNode, setMapNode] = useState<HTMLDivElement | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const [mapZoom, setMapZoom] = useState(14);
  const map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  // Separate layer so toggling the heatmap never rebuilds the person pins.
  const heatLayer = useRef<L.LayerGroup | null>(null);
  const tileLayerRef = useRef<L.TileLayer | null>(null);
  // The mounted PersonCard's root element, so its real on-screen height can
  // be measured to keep the selected friend's pin clear of it (see the
  // selectedId-panning effect below).
  const personCardRef = useRef<HTMLElement | null>(null);
  const didAutoFocus = useRef(false);
  const geofence = useRef(createGeofenceTracker());
  const zoneGeofence = useRef(createZoneGeofenceTracker());
  const locationRef = useRef<LiveLocation | null>(null);
  locationRef.current = location;
  const previewRef = useRef(preview);
  previewRef.current = preview;
  // Realtime handlers need a friend lookup, but must not force useRealtime's
  // effect (channel subscribe/teardown) to rerun on every friends refresh.
  const friendsRef = useRef<Friend[]>([]);
  friendsRef.current = friends;

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
  // earns its haptics. Failures read as fail/error/can't/need in this codebase.
  const toastTimer = useRef<number | null>(null);
  const notify = useCallback((text: string) => {
    haptic(/fail|error|can't|unable|need to first/i.test(text) ? 'warning' : 'success');
    setToast(text);
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => {
      setToast('');
      toastTimer.current = null;
    }, 3200);
  }, []);
  // Clear any pending toast timer on unmount so it can't fire setState afterward.
  useEffect(() => () => {
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
  }, []);

  // While the preference is Auto, follow the OS flipping appearance (sunset on
  // an iPhone, a system schedule on a laptop). An explicit Day/Night choice is
  // never overridden.
  useEffect(() => {
    if (themePref !== 'auto') return;
    return watchSystemTheme(() => applyTheme('auto'));
  }, [themePref]);

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

  const handleFriendLocation = useCallback((userId: string, _row: Record<string, unknown> | null) => {
    // Always re-read through friend_locations so blurred/frozen coords stay
    // masked even if realtime delivered a raw locations row.
    fetchFriendLocation(userId).then((loc) => {
      if (!loc) return;
      setFriends(prev => prev.map(f => (
        f.id === userId ? { ...f, location: loc, ghost_mode: loc.privacy_mode ?? f.ghost_mode } : f
      )));
    }).catch(() => undefined);
  }, []);

  const handleIncomingMessage = useCallback((msg: Message) => {
    pushIncoming(msg);
  }, [pushIncoming]);

  const handleReaction = useCallback((reaction: MapReaction) => {
    haptic('medium');
    setMyReactions(current => [reaction, ...current].slice(0, 30));
    const sender = friendsRef.current.find(f => f.id === reaction.sender_id);
    if (sender) {
      const meta = THROWABLES.find(t => t.emoji === reaction.emoji);
      const key = Date.now();
      setIncomingGift({ sender, emoji: reaction.emoji, label: meta?.label, key });
      window.setTimeout(() => setIncomingGift(current => (current?.key === key ? null : current)), 2600);
    }
  }, []);

  const handlePlaceEvent = useCallback((event: PlaceEvent) => {
    setPlaceEvents(current => [event, ...current].slice(0, 40));
  }, []);

  const handleHighlight = useCallback((highlight: Highlight) => {
    setHighlights(current => ({
      ...current,
      [highlight.user_id]: [highlight, ...(current[highlight.user_id] || [])],
    }));
  }, []);

  const handleGroupMessage = useCallback((msg: Message) => {
    const groupId = msg.group_id;
    if (!groupId) return;
    setGroupThreads(current => {
      const existing = current[groupId];
      if (!existing) return current; // thread not opened yet — it'll load fresh when opened
      if (existing.some(m => m.id === msg.id)) return current;
      return { ...current, [groupId]: [...existing, msg] };
    });
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
    onHighlight: handleHighlight,
    onGroupMessage: handleGroupMessage,
  });

  // Blurred friends never appear on the locations realtime channel (RLS hides
  // the raw row), so pull the masked view on a short interval.
  useEffect(() => {
    if (preview || !profile) return;
    const tick = () => { reloadFriends(profile.id).catch(() => undefined); };
    const id = window.setInterval(tick, 20_000);
    return () => window.clearInterval(id);
  }, [preview, profile, reloadFriends]);

  useEffect(() => {
    const invite = readInviteQuery();
    const token = inviteTokenFromUrl(window.location.href);
    if (invite) setInviteQuery(invite);
    if (token) setPendingInviteToken(token);
    try {
      if (invite || token) window.history.replaceState({}, '', window.location.pathname + window.location.hash);
    } catch {
      // history rewriting is cosmetic
    }
    const apply = (url: string) => {
      const name = usernameFromInviteUrl(url);
      if (name) setInviteQuery(name);
      const t = inviteTokenFromUrl(url);
      if (t) setPendingInviteToken(t);
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
  // coordinate means "Office". Frozen mode should not broadcast movement at all.
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

  // Same idea for Zenlands, except only your own zones can trigger a notice
  // from your own device — a friend's zone is visible so its name resolves
  // in the feed, but only its owner's phone runs the geofence for it.
  const myZones = useMemo(() => zones.filter(z => z.owner_id === profile?.id), [zones, profile?.id]);
  useEffect(() => {
    if (preview || !location || !profile || myZones.length === 0) return;
    if (ghostMode === 'frozen') return;
    const transition = zoneGeofence.current.update(location.lat, location.lng, myZones);
    if (!transition) return;
    recordPlaceEvent(
      profile.id,
      transition.kind,
      transition.zone.label,
      transition.zone.lat,
      transition.zone.lng,
    ).catch(() => undefined);
  }, [location, profile, myZones, ghostMode]);

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
          setLocationLabel('Last saved location');
        }
        await reloadFriends(user.user.id);
        getGhostMode(user.user.id).then(setGhostMode).catch(() => undefined);
        getFriendGhostModes(user.user.id).then(setFriendModes).catch(() => undefined);
        loadMyVisits(user.user.id).then(setMyVisits).catch(() => undefined);
        loadFriendHighlights().then(setHighlights).catch(() => undefined);
        loadVisibleZones().then(setZones).catch(() => undefined);
        loadMyGroups().then(setGroups).catch(() => undefined);
      }
      setProfileLoaded(true);
    })();
  }, [signedIn, reloadFriends, preview]);

  // Open the add-friend sheet automatically when arriving from a legacy
  // username invite link (no token — falls back to the search-and-request flow).
  useEffect(() => {
    if (inviteQuery && profile) setPanel('add');
  }, [inviteQuery, profile]);

  // A token link redeems straight into a mutual friendship — no search step,
  // no waiting on the other side to approve. See redeemInvite/redeem_invite.
  useEffect(() => {
    if (!pendingInviteToken || !profile || preview || !isUserUuid(profile.id) || inviteRedeeming) return;
    const token = pendingInviteToken;
    setInviteRedeeming(true);
    (async () => {
      try {
        const ownerId = await redeemInvite(token);
        if (!ownerId) return; // table/RPC not migrated yet — link just does nothing
        if (ownerId === profile.id) { notify('That\'s your own invite link'); return; }
        const { data: ownerProfile } = await supabase.from('profiles').select('*').eq('id', ownerId).maybeSingle();
        await reloadFriends(profile.id);
        if (ownerProfile) setNewFriendWelcome(ownerProfile as Profile);
        else notify('Friend added!');
      } catch (error) {
        notify(error instanceof Error ? error.message : 'Invite link is invalid or expired');
      } finally {
        setPendingInviteToken('');
        setInviteRedeeming(false);
      }
    })();
  }, [pendingInviteToken, profile, preview, inviteRedeeming, reloadFriends, notify]);

  // Mint my own invite token lazily, the first time I open the add-friend
  // sheet — every share reuses it until the sheet is reopened fresh.
  useEffect(() => {
    if (panel !== 'add' || !profile || preview || !isUserUuid(profile.id) || myInviteToken) return;
    createInviteToken(profile.id).then(setMyInviteToken).catch(() => undefined);
  }, [panel, profile, preview, myInviteToken]);

  // Guarding on signedIn alone let a real, still-persisted Supabase session
  // (e.g. a device previously logged in for real) race the "Preview" button:
  // preview would flip true first, then the async session restore fired
  // signedIn=true a moment later, and this effect — not checking preview —
  // started overwriting the demo location with the device's real live GPS,
  // while every other bit of state stayed the static demo fixture. That
  // produced exactly the "490 km away, riding a bike in LA" nonsense: a
  // demo friend's fixed coordinates paired with a real, far-away position.
  useEffect(() => {
    if (preview || !signedIn || !profile) return;
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
  }, [preview, signedIn, profile, ghostMode]);

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
    // No pan here — the PersonCard sheet hasn't mounted yet, so its real
    // height isn't known. The effect below (keyed on selectedId) does the
    // panning once the card has a measurable layout.
  }, []);

  // Keeps the tapped friend's pin visible above the PersonCard sheet instead
  // of hidden under it. `focusMapOn`'s fixed SHEET_OFFSET_PX (150px) is
  // calibrated for the slim bottom dock — nowhere near enough to clear a
  // sheet that can run up to 69% of the screen on a tall phone, which is
  // exactly what made the friend's pin disappear under the card. Measuring
  // the card's actual rendered height and shifting by half of it centers the
  // pin in whatever strip of map is still visible, on any screen size.
  useEffect(() => {
    if (!selectedId || !map.current || !mapNode) return;
    const loc = friends.find((f) => f.id === selectedId)?.location;
    if (!loc) return;
    const raf = requestAnimationFrame(() => {
      if (!map.current) return;
      const mapHeight = mapNode.getBoundingClientRect().height;
      // Fallback mirrors the sheet's CSS max-height (69%) for the rare case
      // the ref isn't measurable yet, rather than under-shooting to 0.
      const cardHeight = personCardRef.current?.getBoundingClientRect().height
        ?? mapHeight * 0.69;
      const offset = Math.min(cardHeight / 2 + 16, mapHeight * 0.42);
      const z = map.current.getZoom() < 14 ? 16 : map.current.getZoom();
      const pt = map.current.project(L.latLng(loc.lat, loc.lng), z);
      pt.y += offset;
      map.current.flyTo(map.current.unproject(pt, z), z, { animate: true, duration: 0.6 });
    });
    return () => cancelAnimationFrame(raf);
    // Deliberately excludes `friends` — re-panning on every live location tick
    // for the friend already on screen would keep yanking the map while
    // someone is mid-read of the card. Only a fresh selection re-centers.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId, mapNode]);

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
      if (failures >= 4) setMapTileError('Map tiles failed to load — check your network and refresh.');
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
    setMapZoom(instance.getZoom());
    const syncZoom = () => setMapZoom(instance.getZoom());
    instance.on('zoomend', syncZoom);

    return () => {
      window.clearTimeout(t1);
      window.clearTimeout(t2);
      instance.off('zoomend', syncZoom);
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
      loadFriendHighlights().then(setHighlights).catch(() => undefined);
      loadVisibleZones().then(setZones).catch(() => undefined);
      loadMyGroups().then(setGroups).catch(() => undefined);
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
    const located = people.filter((row): row is { p: Profile | Friend; l: LiveLocation; mine?: boolean } => Boolean(row.l));
    // Same-screen overlap becomes a count bubble. Zooming in splits them again
    // because this uses layer pixels, not kilometres.
    const projected = located.map((row) => {
      const pt = map.current!.latLngToLayerPoint(L.latLng(row.l.lat, row.l.lng));
      return { x: pt.x, y: pt.y, data: row };
    });
    clusterByPixels(projected, 58).forEach((group) => {
      if (group.items.length > 1) {
        const lat = group.items.reduce((sum, row) => sum + row.l.lat, 0) / group.items.length;
        const lng = group.items.reduce((sum, row) => sum + row.l.lng, 0) / group.items.length;
        const count = group.items.length;
        const large = count > 4;
        const icon = L.divIcon({
          className: 'people-cluster-shell',
          html: `<div class="people-cluster${large ? ' lg' : ''}">${count}</div>`,
          iconSize: large ? [60, 60] : [52, 52],
          iconAnchor: large ? [30, 30] : [26, 26],
        });
        L.marker([lat, lng], { icon, zIndexOffset: 800 })
          .on('click', () => {
            const bounds = L.latLngBounds(group.items.map(row => L.latLng(row.l.lat, row.l.lng)));
            map.current?.fitBounds(bounds.pad(0.55), { maxZoom: 17, animate: true, duration: 0.55 });
          })
          .addTo(layers.current!);
        return;
      }
      const { p, l, mine } = group.items[0];
      const color = /^#[0-9a-f]{6}$/i.test(p.avatar_color) ? p.avatar_color : '#ff6658';
      const avatarVersion = mine
        ? pinAvatarVersion
        : (p.avatar_url?.length ?? 0) + (p.id?.length ?? 0);
      const face = pinFaceHtml(p.avatar_url, p.display_name, avatarVersion);
      // Green ring = this person is sharing a live fix. Gray ring = they froze
      // sharing, or their last ping is old enough that it is only a last-seen.
      const theirMode = 'ghost_mode' in p ? p.ghost_mode : undefined;
      const hidden = (mine ? ghostMode : theirMode) === 'frozen';
      const stale = Date.now() - new Date(l.updated_at).getTime() > STALE_AFTER_MS;
      const live = !hidden && !stale;
      const reaction = mine ? freshReaction : undefined;
      const moving = fmtSpeed(l.speed);
      const icon = L.divIcon({
        className: 'person-pin-shell',
        html: `<div class="person-pin ${mine ? 'mine' : ''} ${live ? 'live' : 'away'}" style="--pin:${color}"><div class="pin-face">${face}</div><b>${safeHtml(p.status_emoji)}</b>${live ? (moving ? `<i class="pin-speed">${safeHtml(moving)}</i>` : '') : `<i>${safeHtml(ago(l.updated_at))}</i>`}${reaction ? `<u class="pin-reaction">${safeHtml(reaction)}</u>` : ''}</div>`,
        iconSize: [60, 80],
        iconAnchor: [30, 30],
      });
      const marker = L.marker([l.lat, l.lng], { icon, zIndexOffset: mine ? 1000 : 0 }).addTo(layers.current!);
      if (!mine) marker.on('click', () => { const f = friends.find(x => x.id === p.id); if (f) openFriend(f); });
    });
    // Private overnight places, visible only to the signed-in user.
    places.forEach(p => {
      const icon = L.divIcon({
        className: 'place-pin-shell',
        html: `<div class="place-pin" style="--place:#25c9b7"><span>🌙</span><b>${safeHtml(`${p.score} nights`)}</b></div>`,
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
    // Zenlands you created — friend-visible, unlike the overnight places above.
    myZones.forEach(z => {
      const icon = L.divIcon({
        className: 'place-pin-shell',
        html: `<div class="place-pin zone" style="--place:#ff3e86"><span>${safeHtml(z.emoji)}</span><b>${safeHtml(z.label)}</b></div>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      L.marker([z.lat, z.lng], { icon, interactive: false, zIndexOffset: -450 }).addTo(layers.current!);
    });
    // Story pins: a friend's newest still-live, location-tagged highlight —
    // à la Snap Map, separate from their live position pin above. Perfect
    // circle with an IG-style gradient ring, not the teardrop location shape.
    const now = Date.now();
    friends.forEach(f => {
      const latest = (highlights[f.id] || []).find(h => h.lat != null && h.lng != null && new Date(h.expires_at).getTime() > now);
      if (!latest) return;
      const thumb = latest.media_url
        ? `<img src="${safeHtml(latest.media_url)}" alt="" />`
        : `<span class="story-pin-fallback">${safeHtml(f.status_emoji || '📍')}</span>`;
      const icon = L.divIcon({
        className: 'story-pin-shell',
        html: `<div class="story-pin"><i class="story-ring"></i><span class="story-thumb">${thumb}</span></div>`,
        iconSize: [46, 46],
        iconAnchor: [23, 23],
      });
      const marker = L.marker([latest.lat as number, latest.lng as number], { icon, zIndexOffset: 600 }).addTo(layers.current!);
      marker.on('click', () => setHighlightViewerId(f.id));
    });
  }, [friends, location, profile, profile?.avatar_url, places, nearbyPlaces, myZones, highlights, mapReady, mapZoom, freshReaction, openFriend, ghostMode, pinAvatarVersion]);

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
        setLocationLabel('Last saved location');
        map.current?.flyTo([saved.lat, saved.lng], 16, { animate: true, duration: 0.8 });
        notify('Couldn\'t get your current location — reverted to the last saved one');
        return;
      }
      const denied = error instanceof GeolocationPositionError && error.code === error.PERMISSION_DENIED;
      if (denied && isNative) notify('Please allow Pinpop to use location in system settings');
      else if (denied) notify('Please allow Pinpop to use location in your browser settings');
      else notify('Couldn\'t get your location right now — enable location permission and try again');
    } finally {
      setLocating(false);
    }
  }

  async function changeAvatar(file?: File) {
    if (!file || !profile) return;
    setAvatarBusy(true);
    try {
      if (preview || !isUserUuid(profile.id)) {
        const avatarUrl = URL.createObjectURL(file);
        setProfile(current => current ? { ...current, avatar_url: avatarUrl } : current);
        setPinAvatarVersion(version => version + 1);
        notify('Preview mode: your new avatar is set ✨');
        return;
      }
      const avatarUrl = await uploadProfileAvatar(profile.id, file);
      setProfile(current => current ? { ...current, avatar_url: avatarUrl } : current);
      setFriends(current => current.map(f => f.id === profile.id ? { ...f, avatar_url: avatarUrl } : f));
      setPinAvatarVersion(version => version + 1);
      notify('Your new avatar is set ✨');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Avatar upload failed — please try again later');
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
      notify(status === 'accepted' ? 'You\'re now friends 🎉' : 'Request dismissed');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Action failed — please try again later');
    } finally {
      setRequestBusy(prev => { const next = new Set(prev); next.delete(relId); return next; });
    }
  }

  async function changeGhostMode(mode: GhostMode) {
    if (!profile) return;
    const previous = ghostMode;
    setGhostMode(mode);
    const label = GHOST_MODES.find(m => m.value === mode)?.title ?? mode;
    if (preview || !isUserUuid(profile.id)) {
      notify(`Preview mode: switched to ${label}`);
      return;
    }
    try {
      await persistGhostMode(profile.id, mode, location ? { lat: location.lat, lng: location.lng } : undefined);
      notify(`Switched to ${label} — friends see the position the server computes`);
    } catch (error) {
      setGhostMode(previous);
      notify(error instanceof Error ? error.message : 'Failed to save privacy setting');
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
      notify(error instanceof Error ? error.message : 'Failed to save per-friend setting');
    }
  }

  async function saveStatus(emoji: string, text: string) {
    if (!profile) return { error: 'Your session has expired' };
    try {
      await updateStatus(profile.id, emoji, text);
      setProfile(current => current ? { ...current, status_emoji: emoji, status_text: text } : current);
      notify('Status updated');
      return {};
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Failed to save status' };
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
      notify(error instanceof Error ? error.message : 'Action failed');
    }
  }

  async function reactTo(friend: Friend, emoji: string) {
    if (!profile) return;
    haptic('medium');
    try {
      await sendReaction(profile.id, friend.id, emoji);
      notify(`Sent ${emoji} to ${friend.display_name}`);
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Couldn\'t send that reaction');
    }
  }

  async function confirmDeleteAccount() {
    setDeleting(true);
    try {
      await deleteMyAccount();
      // The auth listener tears down the rest of the state on sign-out.
      setDeleteArmed(false);
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Delete failed — please try again later');
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
      mine ? 'Pinpop friend invite' : `Add ${target.display_name} on Pinpop`,
      text,
      inviteUrl(target.username),
    );
    if (result === 'cancelled') return;
    notify(result === 'shared' ? 'Shared ✨' : 'Link copied — send it to a friend to add you');
  }

  async function waveAtEveryone() {
    if (!profile || waving) return;
    if (!friends.length) {
      notify('Add some friends first, then wave at them');
      setPanel('add');
      return;
    }
    setWaving(true);
    try {
      const result = await waveAll(friends.map(f => f.id));
      notify(result.failed
        ? `Waved at ${result.sent} friends, ${result.failed} failed`
        : `Waved at ${result.sent} friends 👋`);
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
    if (!profile || !location) return { error: 'Turn on location before checking in' };
    const result = await checkIn(profile.id, { ...input, lat: location.lat, lng: location.lng });
    if (result.error) return { error: result.error };
    setCheckInOpen(false);
    notify('Checked in 📍');
    loadMyVisits(profile.id).then(setMyVisits).catch(() => undefined);
    refreshNearby();
    return {};
  }

  async function submitHighlight(input: { body: string; file: File | null; attachLocation: boolean }) {
    if (!profile) return { error: 'Your session has expired' };
    if (preview || !isUserUuid(profile.id)) {
      setPostingHighlight(false);
      notify('Preview mode: story posted ✨');
      return {};
    }
    setHighlightBusy(true);
    try {
      const mediaUrl = input.file ? await uploadHighlightPhoto(profile.id, input.file) : null;
      const geo = input.attachLocation && location ? { lat: location.lat, lng: location.lng } : null;
      await postHighlight(profile.id, input.body, mediaUrl, geo);
      setHighlights(current => ({
        ...current,
        [profile.id]: [
          {
            id: `local-${Date.now()}`, user_id: profile.id, body: input.body.trim(), media_url: mediaUrl,
            created_at: new Date().toISOString(), expires_at: new Date(Date.now() + 86_400_000).toISOString(),
            lat: geo?.lat ?? null, lng: geo?.lng ?? null,
          },
          ...(current[profile.id] || []),
        ],
      }));
      setPostingHighlight(false);
      notify('Story posted — friends can see it for the next 24 hours ✨');
      loadFriendHighlights().then(setHighlights).catch(() => undefined);
      return {};
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Post failed — please try again later' };
    } finally {
      setHighlightBusy(false);
    }
  }

  async function removeHighlight(id: string) {
    if (!profile) return;
    setHighlights(current => ({
      ...current,
      [profile.id]: (current[profile.id] || []).filter(h => h.id !== id),
    }));
    if (id.startsWith('local-')) return;
    try {
      await deleteHighlight(id);
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Delete failed — please try again later');
      loadFriendHighlights().then(setHighlights).catch(() => undefined);
    }
  }

  async function submitZone(label: string, emoji: string, lat: number, lng: number) {
    if (!profile) return { error: 'Your session has expired' };
    if (preview || !isUserUuid(profile.id)) {
      notify('Preview mode: Zenland created ✨');
      return {};
    }
    try {
      const zone = await createZone(profile.id, label, emoji, lat, lng);
      setZones(current => [zone, ...current]);
      notify(`"${zone.label}" created — friends can see it now`);
      return {};
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Create failed — please try again later' };
    }
  }

  async function removeZone(id: string) {
    const previous = zones;
    setZones(current => current.filter(z => z.id !== id));
    if (preview) return;
    try {
      await deleteZone(id);
    } catch (error) {
      setZones(previous);
      notify(error instanceof Error ? error.message : 'Delete failed — please try again later');
    }
  }

  async function submitCreateGroup(input: { name: string; memberIds: string[] }) {
    if (!profile) return { error: 'Your session has expired' };
    if (preview || !isUserUuid(profile.id)) {
      notify('Preview mode: group chat created ✨');
      setCreatingGroup(false);
      return {};
    }
    try {
      const group = await createGroup(profile.id, input.name, input.memberIds);
      const members = friends.filter(f => input.memberIds.includes(f.id));
      const full: ChatGroup = {
        ...group,
        members: [profile, ...members],
      };
      setGroups(current => [full, ...current]);
      setCreatingGroup(false);
      setOpenGroupId(group.id);
      setGroupThreads(current => ({ ...current, [group.id]: [] }));
      notify(`"${group.name}" created`);
      return {};
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Create failed — please try again later' };
    }
  }

  async function openGroupChat(groupId: string) {
    setOpenGroupId(groupId);
    if (groupThreads[groupId]) return;
    try {
      const thread = await loadGroupThread(groupId);
      setGroupThreads(current => ({ ...current, [groupId]: thread }));
    } catch {
      setGroupThreads(current => ({ ...current, [groupId]: [] }));
    }
  }

  async function sendGroupChatMessage(groupId: string, text: string) {
    if (!profile) return { error: 'Your session has expired' };
    if (preview || !isUserUuid(profile.id)) {
      const optimistic: Message = {
        id: `local-${Date.now()}`,
        sender_id: profile.id,
        recipient_id: null,
        group_id: groupId,
        body: text,
        kind: 'text',
        created_at: new Date().toISOString(),
      } as Message;
      setGroupThreads(current => ({ ...current, [groupId]: [...(current[groupId] || []), optimistic] }));
      return {};
    }
    const result = await sendGroupMessage(profile.id, groupId, text);
    if (!result.error) {
      const thread = await loadGroupThread(groupId).catch(() => null);
      if (thread) setGroupThreads(current => ({ ...current, [groupId]: thread }));
    }
    return result;
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

  const highlightAuthor = useMemo<Profile | Friend | null>(() => {
    if (!highlightViewerId) return null;
    if (highlightViewerId === profile?.id) return profile;
    return friends.find(f => f.id === highlightViewerId) ?? null;
  }, [highlightViewerId, profile, friends]);

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
        if (!user.user) return { error: 'Your session has expired — please log in again' };
        const result = await completeProfile(user.user.id, username, displayName);
        if (result.error) return { error: result.error };
        if (result.profile) setProfile(result.profile);
        return {};
      }} />
    );
  }

  const sheetCopy: Record<string, { eyebrow: string; title: string }> = {
    friends: { eyebrow: 'Your circle', title: `${friends.length} friends` },
    places: { eyebrow: 'Happening nearby', title: 'Explore' },
    world: { eyebrow: 'Your world', title: 'My profile' },
    messages: { eyebrow: 'Stay in touch', title: 'Messages' },
    settings: { eyebrow: 'Location privacy', title: 'Ghost Mode' },
    notifications: { eyebrow: 'Latest activity', title: 'Notifications' },
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
              <p>Location permission was denied, so friends can't see you. {isNative ? 'Allow "While Using" or "Always" in system settings.' : 'Re-allow location in your browser\'s address bar permissions.'}</p>
              {isNative ? (
                <button type="button" className="primary compact" onClick={() => { haptic('light'); openAppSettings(); }}>
                  Open settings
                </button>
              ) : (
                <button type="button" className="primary compact" onClick={locateMe} disabled={locating}>
                  {locating ? 'Locating…' : 'Retry'}
                </button>
              )}
            </>
          ) : (
            <>
              <p>Turn on location and you'll show up on the map.</p>
              <button type="button" className="primary compact" onClick={() => { haptic('light'); locateMe(); }} disabled={locating}>
                {locating ? 'Locating…' : 'Turn on location'}
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
            <button className="demo-badge" type="button" onClick={() => setPreview(false)}>Preview</button>
          )}
          <button className="circle-button" type="button" onClick={() => setPanel('notifications')} aria-label="Notifications">
            <Bell size={20} />
            {notificationCount > 0 && <span className="dot-badge">{notificationCount > 9 ? '9+' : notificationCount}</span>}
          </button>
          <button className={`circle-button ${ghostMode !== 'precise' ? 'active' : ''}`} type="button" onClick={() => setPanel('settings')}><Ghost size={21} /></button>
        </div>
      </header>

      <div className="map-tools">
        <button type="button" onClick={locateMe} disabled={locating} aria-label="Locate me">
          {locating ? <Loader2 size={21} className="spin" /> : <LocateFixed size={21} />}
        </button>
        <button type="button" onClick={() => setPanel('places')} aria-label="Explore nearby"><MapPin size={21} /></button>
        <button
          type="button"
          className={`theme-toggle ${themePref !== 'auto' ? 'active' : ''}`}
          onClick={() => {
            haptic('select');
            const next = THEME_CYCLE[(THEME_CYCLE.indexOf(themePref) + 1) % THEME_CYCLE.length];
            setThemePref(next);
            storeThemePreference(next);
            applyTheme(next);
            notify(`Theme: ${THEME_LABEL[next]}`);
          }}
          aria-label={`Theme: ${THEME_LABEL[themePref]}. Tap to change.`}
          title={`Theme: ${THEME_LABEL[themePref]}`}
        >
          {themePref === 'auto' ? <SunMoon size={21} />
            : themePref === 'light' ? <Sun size={21} />
              : <Moon size={21} />}
        </button>
      </div>

      <nav className="dock">
        <button className={panel === 'friends' ? 'active' : ''} type="button" onClick={() => switchPanel('friends')}><Users /><span>Friends</span></button>
        <button className={panel === 'places' ? 'active' : ''} type="button" onClick={() => switchPanel('places')}><Search /><span>Explore</span></button>
        <button className="center-action" type="button" disabled={waving} onClick={() => { haptic('heavy'); waveAtEveryone(); }} aria-label="Wave at all friends">
          <span>{waving ? '…' : '👋'}</span>
        </button>
        <button className={panel === 'world' ? 'active' : ''} type="button" onClick={() => switchPanel('world')}><User /><span>Me</span></button>
        <button className={panel === 'messages' ? 'active' : ''} type="button" onClick={() => switchPanel('messages')}>
          <MessageCircle /><span>Messages</span>
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
          inviteToken={myInviteToken}
          onClose={() => { setInviteQuery(''); setPanel('friends'); }}
          onSearch={(q) => { searchProfiles(profile.id, q).then(setAddResults).catch(() => undefined); }}
          onSendRequest={async (id) => {
            const outcome = await sendFriendRequest(profile.id, id);
            if (outcome === 'accepted') {
              await reloadFriends(profile.id);
              notify('They had already added you too — you\'re now friends 🎉');
              return;
            }
            setSentIds(prev => new Set(prev).add(id));
            notify(outcome === 'already_friends' ? 'You\'re already friends' : 'Friend request sent');
          }}
          onNotify={notify}
        />
      )}

      {checkInOpen && location && (
        <CheckInPanel location={location} onClose={() => setCheckInOpen(false)} onSubmit={submitCheckIn} />
      )}

      {postingHighlight && (
        <PostHighlightSheet location={location} onClose={() => setPostingHighlight(false)} onSubmit={submitHighlight} />
      )}

      {highlightViewerId && highlightAuthor && (highlights[highlightViewerId]?.length ?? 0) > 0 && (
        <HighlightViewer
          author={highlightAuthor}
          isMine={highlightViewerId === profile.id}
          highlights={highlights[highlightViewerId] || []}
          onClose={() => setHighlightViewerId(null)}
          onDelete={removeHighlight}
        />
      )}

      {newFriendWelcome && (
        <InviteWelcomeCard
          friend={newFriendWelcome}
          onClose={() => setNewFriendWelcome(null)}
          onOpenChat={() => { openChat(newFriendWelcome.id); setNewFriendWelcome(null); }}
        />
      )}

      {creatingGroup && (
        <NewGroupSheet friends={friends} onClose={() => setCreatingGroup(false)} onSubmit={submitCreateGroup} />
      )}

      {openGroupId && (() => {
        const group = groups.find(g => g.id === openGroupId);
        if (!group) return null;
        return (
          <GroupChatPanel
            group={group}
            messages={groupThreads[openGroupId] || []}
            meId={profile.id}
            onClose={() => setOpenGroupId(null)}
            onSend={(text) => sendGroupChatMessage(openGroupId, text)}
          />
        );
      })()}

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
              <HighlightsRail
                me={profile}
                friends={friends}
                highlights={highlights}
                busy={highlightBusy}
                onAddMine={() => setPostingHighlight(true)}
                onOpen={setHighlightViewerId}
              />
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
              <div className="search"><Search size={18} /><input placeholder="Search friends" value={search} onChange={e => setSearch(e.target.value)} /></div>
              <div className="friend-list">
                {filtered.length === 0 && (
                  <div className="empty-state">
                    <span className="empty-art">{friends.length ? '🔍' : '👋'}</span>
                    {friends.length ? (
                      <>
                        <b>No matching friends</b>
                        <p>Try a different name, or search by @username.</p>
                      </>
                    ) : (
                      <>
                        <b>No friends yet</b>
                        <p>Send your card link to friends — one tap and they're added.</p>
                        <button className="primary compact" type="button" onClick={() => setPanel('add')}>Add friend</button>
                      </>
                    )}
                  </div>
                )}
                {filtered.map(f => {
                  const streak = streakInfo(f.streak_days, f.last_interaction_on, f.streak_grace_value, f.streak_grace_days);
                  return (
                  <button className="friend-row" key={f.id} type="button" onClick={() => openFriend(f)}>
                    <Avatar profile={f} showStatus />
                    <div>
                      <b>
                        {f.is_best_friend && <Star size={12} className="best-star" />}
                        {f.display_name}
                        {streak.days > 0 && (
                          <i className={`streak-chip ${streak.tier} ${streak.atRisk ? 'at-risk' : ''}`}>
                            {streak.atRisk ? '⏳' : streak.icon}{streak.days}
                          </i>
                        )}
                        {streak.repairing && <i className="streak-chip repairing">🩹{3 - streak.repairDaysLeft}/3</i>}
                        {streak.canRepair && <i className="streak-chip can-repair">💔</i>}
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
                  );
                })}
              </div>
              <button className="share-card-button" type="button" onClick={() => shareCard(profile)}>
                <Share2 size={16} />
                <div><b>Share my card</b><small>One tap on the link and they're added</small></div>
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
                    <span>{avatarBusy ? 'Uploading…' : 'Change avatar'}</span>
                    <input type="file" accept="image/*" disabled={avatarBusy} onChange={e => {
                      const file = e.target.files?.[0];
                      e.target.value = '';
                      void changeAvatar(file);
                    }} />
                  </label>
                </div>
                <div><span>@{profile.username}</span><strong>{profile.display_name}</strong><small>Makes you easy to spot on the map</small></div>
              </div>

              <button className="share-card-button" type="button" onClick={() => shareCard(profile)}>
                <Share2 size={16} />
                <div><b>Share my card</b><small>Send the link — one tap and they're added</small></div>
              </button>

              <StatusEditor profile={profile} onSave={saveStatus} />

              <div className="eyebrow">My check-ins</div>
              {myVisits.length === 0 ? (
                <p className="muted empty-hint">No check-ins yet — head to "Explore" to check in.</p>
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
                        <b>{visit.place?.name || 'Unknown place'}</b>
                        <small>{visit.note || (visit.visibility === 'private' ? 'Only me' : 'Friends can see')}</small>
                      </div>
                      <span className="friend-meta">{ago(visit.arrived_at)}</span>
                    </button>
                  ))}
                </div>
              )}

              <div className="eyebrow">Footprints & heatmap</div>
              <FootprintsPanel
                heatVisible={heatVisible}
                onToggleHeat={(next) => { haptic('select'); setHeatVisible(next); }}
                onHeatLoaded={setHeatCells}
                onFocusPlace={focusMapOn}
                preview={preview}
              />

              <ZonesSection
                myZones={myZones}
                location={location}
                onCreate={submitZone}
                onDelete={removeZone}
                onFocus={focusMapOn}
              />

              <div className="eyebrow">Overnight spots</div>
              {places.length === 0 ? (
                <p className="muted empty-hint">No footprint data yet — keep the app open and your frequent spots will be recorded automatically.</p>
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
                        <small>{p.score} nights</small>
                      </div>
                    </button>
                  ))}
                </div>
              )}

              <div className="privacy-note">
                <Ghost size={19} />
                <div><b>Overnight spots are private to you</b><small>Nights and location are only saved to your own account</small></div>
              </div>

              <button className="danger-button" type="button" onClick={preview ? () => setPreview(false) : signOut}>
                <LogOut size={17} /> {preview ? 'Exit preview' : 'Log out'}
              </button>
            </div>
          )}

          {panel === 'messages' && (
            <div className="friend-list">
              {friends.length === 0 && (
                <div className="empty-state">
                  <p className="muted empty-hint">Add friends to start chatting</p>
                  <button className="primary compact" type="button" onClick={() => setPanel('add')}>Add friend</button>
                </div>
              )}

              <div className="eyebrow">Group chats</div>
              <button
                className="friend-row group-pick-row"
                type="button"
                onClick={() => setCreatingGroup(true)}
                disabled={friends.length < 2}
              >
                <span className="avatar" style={{ background: '#7b6cf6' }}><Users size={18} /></span>
                <div><b>New group chat</b><small>{friends.length < 2 ? 'Need at least 2 friends' : 'Bring friends together'}</small></div>
              </button>
              {groups.map(g => {
                const thread = groupThreads[g.id];
                const last = thread?.[thread.length - 1];
                return (
                  <button className="friend-row" key={g.id} type="button" onClick={() => openGroupChat(g.id)}>
                    <div className="group-avatars">
                      {g.members.slice(0, 3).map(m => <Avatar key={m.id} profile={m} className="group-avatar-stack" />)}
                    </div>
                    <div>
                      <b>{g.name}</b>
                      <small>{last ? last.body : `${g.members.length} members`}</small>
                    </div>
                    {last && <small>{ago(last.created_at)}</small>}
                  </button>
                );
              })}

              <div className="eyebrow">Friends</div>
              {friends.map(f => {
                const thread = threads[f.id] || [];
                const last = thread[thread.length - 1];
                const count = unread[f.id] || 0;
                return (
                  <button className="friend-row" key={f.id} type="button" onClick={() => openChat(f.id)}>
                    <Avatar profile={f} showStatus />
                    <div>
                      <b>{f.display_name}</b>
                      <small className={count ? 'strong' : ''}>{last ? last.body : 'Start chatting…'}</small>
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
              <p>Choose how precisely friends see your location on the map. Blurred and Frozen are both handled server-side — friends never get your real coordinates.</p>
              {GHOST_MODES.map(m => (
                <button key={m.value} type="button" className={ghostMode === m.value ? 'selected' : ''} onClick={() => changeGhostMode(m.value)}>
                  <span>{m.icon}</span>
                  <div><b>{m.title}</b><small>{m.detail}</small></div>
                  <i />
                </button>
              ))}

              <div className="eyebrow">Per-friend override</div>
              {friends.length === 0 ? (
                <p className="muted empty-hint">Add friends to set overrides for them individually.</p>
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
                        >Default</button>
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

              <div className="eyebrow">Legal</div>
              <a
                className="privacy-note link"
                href={PRIVACY_POLICY_URL}
                target="_blank"
                rel="noreferrer"
              >
                <ShieldCheck size={19} />
                <div><b>Privacy policy</b><small>What we collect, how sharing modes work, and how to delete your data</small></div>
                <ExternalLink size={15} className="external-icon" />
              </a>

              <div className="eyebrow">Account</div>
              <div className="danger-zone">
                {deleteArmed ? (
                  <>
                    <p className="danger-copy">
                      Deleting permanently erases your location, friends, messages, and check-ins — this can't be undone.
                    </p>
                    <div className="chip-row">
                      <button className="chip" type="button" onClick={() => setDeleteArmed(false)} disabled={deleting}>
                        Cancel
                      </button>
                      <button className="danger-button solid" type="button" onClick={confirmDeleteAccount} disabled={deleting}>
                        {deleting ? 'Deleting…' : 'Confirm permanent delete'}
                      </button>
                    </div>
                  </>
                ) : (
                  <button className="danger-button" type="button" onClick={() => { haptic('warning'); setDeleteArmed(true); }}>
                    Delete account
                  </button>
                )}
              </div>
            </div>
          )}
        </aside>
      )}

      {selected && (
        <PersonCard
          ref={personCardRef}
          person={selected}
          myLocation={location}
          onClose={() => setSelectedId(null)}
          onChat={() => { openChat(selected.id); setSelectedId(null); }}
          onWave={async () => {
            const result = await wave(selected.id);
            notify(result.error || `Waved at ${selected.display_name} 👋`);
          }}
          onWhatsUp={async () => {
            const result = await whatsUp(selected.id);
            notify(result.error || `Asked ${selected.display_name} what's up 👀`);
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
      {incomingGift && (
        <GiftToast key={incomingGift.key} sender={incomingGift.sender} emoji={incomingGift.emoji} label={incomingGift.label} />
      )}
    </main>
  );
}

export default App;
