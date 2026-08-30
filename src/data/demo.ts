import type { Friend, LiveLocation, Profile } from '../types';

export const demoMe: Profile = {
  id: 'me', username: 'leo', display_name: 'Leo', avatar_color: '#ff6658',
  status_emoji: '☕️', status_text: '在咖啡店', battery_level: 78, is_charging: false,
};

const now = Date.now();
export const demoLocation: LiveLocation = {
  user_id: 'me', lat: 34.0195, lng: -118.4912, accuracy: 15, updated_at: new Date().toISOString(),
};

export const demoFriends: Friend[] = [
  { id: 'maya', username: 'maya', display_name: 'Maya', avatar_color: '#8b7cf6', status_emoji: '🎧', status_text: '听音乐', battery_level: 62, location: { user_id: 'maya', lat: 34.0158, lng: -118.4972, updated_at: new Date(now - 2 * 60000).toISOString() } },
  { id: 'alex', username: 'alex', display_name: 'Alex', avatar_color: '#20bfa9', status_emoji: '🏄', status_text: '在海边', battery_level: 34, location: { user_id: 'alex', lat: 34.0112, lng: -118.4946, updated_at: new Date(now - 8 * 60000).toISOString() } },
  { id: 'nora', username: 'nora', display_name: 'Nora', avatar_color: '#f4a62a', status_emoji: '📚', status_text: '学习中', battery_level: 91, is_charging: true, location: { user_id: 'nora', lat: 34.0255, lng: -118.4882, updated_at: new Date(now - 24 * 60000).toISOString() } },
];
