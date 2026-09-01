export type GhostMode = 'precise' | 'blurred' | 'frozen';

export interface Profile {
  id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  avatar_color: string;
  status_emoji: string;
  status_text: string;
  battery_level?: number | null;
  is_charging?: boolean;
}

export interface LiveLocation {
  user_id: string;
  lat: number;
  lng: number;
  // Both columns are nullable, and background fixes often omit speed.
  accuracy?: number | null;
  speed?: number | null;
  updated_at: string;
  /** Present when the row came from friend_locations. */
  privacy_mode?: GhostMode;
}

export interface Friend extends Profile {
  location?: LiveLocation | null;
  ghost_mode?: GhostMode;
  /** Consecutive days the two of you have exchanged a message or a throw. */
  streak_days?: number;
  /** UTC date (YYYY-MM-DD) the streak was last bumped — used to tell a live
   *  streak from one the server just has not zeroed out yet. */
  last_interaction_on?: string | null;
  /** Set while a missed day is mid-repair — see bump_friend_streak(). */
  streak_grace_value?: number | null;
  streak_grace_days?: number;
  is_best_friend?: boolean;
}

export interface FriendRequest {
  relId: string;
  profile: Profile;
}

/** A "people you may know" candidate — a friend of one of your friends, not
 *  yet a friend (or pending/blocked) yourself. `mutual_name` is one of the
 *  friends who introduces them, for a "Friends with ___" label; `mutual_count`
 *  is how many of your friends they actually share, in case there's more
 *  than one. */
export interface SuggestedFriend extends Profile {
  mutual_count: number;
  mutual_name: string;
}

export type MessageKind = 'text' | 'emoji' | 'wave' | 'image' | 'location' | 'whats_up';

export interface Message {
  id: string;
  sender_id: string;
  /** Null for a group message — `group_id` is set instead. */
  recipient_id: string | null;
  body: string;
  created_at: string;
  kind?: MessageKind;
  read_at?: string | null;
  group_id?: string | null;
}

export type PlaceCategory = 'cafe' | 'food' | 'home' | 'work' | 'park' | 'gym' | 'shop' | 'other';

export interface CheckInPlace {
  id: string;
  name: string;
  category: PlaceCategory;
  address?: string | null;
  lat: number;
  lng: number;
  created_by?: string | null;
}

export interface NearbyPlace extends CheckInPlace {
  distanceKm: number;
}

export type VisitVisibility = 'private' | 'friends' | 'public';

export interface Visit {
  id: string;
  user_id: string;
  place_id: string;
  arrived_at: string;
  visibility: VisitVisibility;
  note?: string | null;
  place?: CheckInPlace | null;
}

export type Panel = 'friends' | 'places' | 'world' | 'messages' | 'settings' | 'add' | 'notifications' | null;

export interface FriendshipRow {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: 'pending' | 'accepted' | 'declined';
  streak_days?: number;
  longest_streak?: number;
  streak_grace_value?: number | null;
  streak_grace_days?: number;
  last_interaction_on?: string | null;
}

/** One grid cell of your own history, used for the footprint heatmap. */
export interface HeatCell {
  cell_lat: number;
  cell_lng: number;
  lat: number;
  lng: number;
  hits: number;
}

export interface FrequentPlace {
  cell_lat: number;
  cell_lng: number;
  lat: number;
  lng: number;
  visits: number;
  minutes: number;
  last_seen: string;
  /** Filled in lazily by reverse geocoding, which is rate limited. */
  label?: string;
}

export interface MapReaction {
  id: string;
  sender_id: string;
  target_id: string;
  emoji: string;
  created_at: string;
}

export type PlaceEventKind = 'arrive' | 'leave';

export interface PlaceEvent {
  id: string;
  user_id: string;
  kind: PlaceEventKind;
  label: string;
  lat?: number | null;
  lng?: number | null;
  created_at: string;
}

/** A 24h-expiring photo post, à la Zenly/Snap "highlights". RLS only ever
 *  hands back your own and your friends' still-live ones. */
export interface Highlight {
  id: string;
  user_id: string;
  body: string;
  media_url?: string | null;
  created_at: string;
  expires_at: string;
  /** Where it was posted, when the author chose to attach a location — shows
   *  up as a story pin on the map, à la Snap Map, until it expires. */
  lat?: number | null;
  lng?: number | null;
}

/** A "Zenland": a friend-visible, hand-named place (unlike the private,
 *  auto-detected significant places). Friends see the label so an
 *  arrive/leave notice reads as "arrived at the Gym" instead of a private clue. */
export interface Zone {
  id: string;
  owner_id: string;
  label: string;
  emoji: string;
  lat: number;
  lng: number;
  radius_m: number;
  created_at: string;
}

export interface ChatGroup {
  id: string;
  name: string;
  owner_id: string;
  created_at: string;
  members: Profile[];
}
