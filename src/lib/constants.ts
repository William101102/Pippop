import type { GhostMode } from '../types';

export const STATUSES = [
  { emoji: '🏠', text: 'At home' },
  { emoji: '💼', text: 'Working' },
  { emoji: '🍔', text: 'Eating' },
  { emoji: '🎧', text: 'Chilling' },
  { emoji: '🚶', text: 'Out for a walk' },
] as const;

export const PALETTE = [
  { ring: '#ff77a9', tint: '#ffe3ee' },
  { ring: '#8b7cf6', tint: '#e9e5ff' },
  { ring: '#25c9b7', tint: '#d7f6f1' },
  { ring: '#ffb03a', tint: '#fff0d4' },
  { ring: '#5ac8e0', tint: '#d6f2f9' },
  { ring: '#9b8cff', tint: '#e9e5ff' },
  { ring: '#43c9a0', tint: '#d6f6ec' },
  { ring: '#ff9f45', tint: '#ffe9d1' },
] as const;

export const ME_COLOR = { ring: '#ff6f61', tint: '#ffe1dc' } as const;
export const MAP_FOCUS_ZOOM = 16;
export const SHEET_OFFSET_PX = 150;
export const USERNAME_RE = /^[a-z0-9_]{3,20}$/;

export const GHOST_MODES: { value: GhostMode; title: string; detail: string; icon: string }[] = [
  { value: 'precise', title: 'Precise', detail: 'Shows your exact location live', icon: '◎' },
  { value: 'blurred', title: 'Blurred', detail: 'Randomly offset by about 0.2–1.2 km', icon: '◌' },
  { value: 'frozen', title: 'Frozen', detail: 'Stuck at your last shared spot', icon: '❄' },
];
