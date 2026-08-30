import type { GhostMode } from '../types';

export const STATUSES = [
  { emoji: '🏠', text: '在家' },
  { emoji: '💼', text: '工作中' },
  { emoji: '🍔', text: '吃饭中' },
  { emoji: '🎧', text: '放松中' },
  { emoji: '🚶', text: '散步中' },
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
  { value: 'precise', title: '精确位置', detail: '实时显示你的准确位置', icon: '◎' },
  { value: 'blurred', title: '模糊位置', detail: '随机偏移约 0.2–1.2 km', icon: '◌' },
  { value: 'frozen', title: '冻结位置', detail: '停留在上一次的位置', icon: '❄' },
];
