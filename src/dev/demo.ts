/**
 * Development-only demo fixtures. Do not import from the production app shell.
 */
import type { Friend, LiveLocation, Profile } from '../types';

export const demoMe: Profile = {
  id: 'demo-me',
  username: 'leo',
  display_name: 'Leo',
  avatar_color: '#ff6658',
  status_emoji: '☕️',
  status_text: '在咖啡店',
  battery_level: 78,
  is_charging: false,
};

const now = Date.now();
export const demoLocation: LiveLocation = {
  user_id: 'demo-me',
  lat: 34.0195,
  lng: -118.4912,
  accuracy: 15,
  updated_at: new Date().toISOString(),
};

export const demoFriends: Friend[] = [
  {
    id: 'demo-maya',
    username: 'maya',
    display_name: 'Maya',
    avatar_color: '#8b7cf6',
    status_emoji: '🎧',
    status_text: '听音乐',
    battery_level: 62,
    location: { user_id: 'demo-maya', lat: 34.0158, lng: -118.4972, updated_at: new Date(now - 2 * 60000).toISOString() },
  },
];
