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
  accuracy?: number | null;
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

export interface Message {
  id: string;
  sender_id: string;
  recipient_id: string;
  body: string;
  created_at: string;
}

export type Panel = 'friends' | 'places' | 'world' | 'messages' | 'settings' | 'add' | null;

export interface FriendshipRow {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: 'pending' | 'accepted' | 'declined';
}
