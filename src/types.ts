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
}

export interface Friend extends Profile {
  location?: LiveLocation | null;
  ghost_mode?: GhostMode;
  /** Consecutive days the two of you have exchanged a message. */
  streak_days?: number;
  is_best_friend?: boolean;
}

export interface FriendRequest {
  relId: string;
  profile: Profile;
}

export type MessageKind = 'text' | 'emoji' | 'wave' | 'image' | 'location' | 'whats_up';

export interface Message {
  id: string;
  sender_id: string;
  recipient_id: string;
  body: string;
  created_at: string;
  kind?: MessageKind;
  read_at?: string | null;
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
