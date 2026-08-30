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
  accuracy?: number;
  speed?: number | null;
  updated_at: string;
}

export interface Friend extends Profile {
  location?: LiveLocation | null;
  ghost_mode?: GhostMode;
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
}
