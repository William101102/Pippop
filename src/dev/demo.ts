/**
 * In-app preview fixtures so the map can be shown without a session.
 * IDs are not UUIDs, so live writes (location upsert, friends reload) stay off.
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
  speed: 0,
  updated_at: new Date(now).toISOString(),
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
    is_best_friend: true,
    streak_days: 14,
    location: {
      user_id: 'demo-maya',
      lat: 34.0158,
      lng: -118.4972,
      speed: 1.2,
      updated_at: new Date(now - 2 * 60_000).toISOString(),
    },
  },
  {
    id: 'demo-noah',
    username: 'noah',
    display_name: 'Noah',
    avatar_color: '#25c9b7',
    status_emoji: '🚴',
    status_text: '骑车中',
    battery_level: 41,
    is_charging: true,
    streak_days: 3,
    location: {
      user_id: 'demo-noah',
      lat: 34.0254,
      lng: -118.4795,
      speed: 6.4,
      updated_at: new Date(now - 20_000).toISOString(),
    },
  },
  {
    id: 'demo-aya',
    username: 'aya',
    display_name: 'Aya',
    avatar_color: '#ffb03a',
    status_emoji: '🏠',
    status_text: '在家',
    battery_level: 93,
    ghost_mode: 'frozen',
    location: {
      user_id: 'demo-aya',
      lat: 34.0312,
      lng: -118.5104,
      updated_at: new Date(now - 3 * 60 * 60_000).toISOString(),
    },
  },
  {
    id: 'demo-jun',
    username: 'jun',
    display_name: 'Jun',
    avatar_color: '#5ac8e0',
    status_emoji: '💼',
    status_text: '工作中',
    battery_level: 54,
    streak_days: 7,
    location: {
      user_id: 'demo-jun',
      lat: 34.011,
      lng: -118.495,
      updated_at: new Date(now - 8 * 60_000).toISOString(),
    },
  },
];
