import { PALETTE } from './constants';

export function colorFor(username: string) {
  let h = 0;
  for (const c of username) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}

export function tintFor(ring: string) {
  const found = PALETTE.find((p) => p.ring.toLowerCase() === ring.toLowerCase());
  return found ? found.tint : '#f1f1f1';
}

export function colorForProfile(avatarColor?: string | null, username?: string) {
  if (avatarColor) return { ring: avatarColor, tint: tintFor(avatarColor) };
  return colorFor(username || 'x');
}
