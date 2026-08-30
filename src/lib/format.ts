export function esc(s: string) {
  return String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!,
  );
}

export function initials(name: string) {
  return name.trim().slice(0, 1).toUpperCase();
}

export function timeAgo(iso?: string) {
  if (!iso) return '暂无定位';
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return '刚刚';
  if (s < 3600) return `${Math.floor(s / 60)} 分钟前`;
  if (s < 86400) return `${Math.floor(s / 3600)} 小时前`;
  return `${Math.floor(s / 86400)} 天前`;
}

export function fmtDist(km: number) {
  if (km < 1) return `${Math.round(km * 1000)} m`;
  return `${km.toFixed(1)} km`;
}

/** Geolocation speed is metres/second. Below a walk it reads as noise. */
export function fmtSpeed(mps?: number | null) {
  if (mps == null || !Number.isFinite(mps) || mps < 0.8) return null;
  return `${Math.round(mps * 3.6)} km/h`;
}

const POINTS = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'] as const;

export function compassLabel(deg: number) {
  const idx = Math.round(((deg % 360) + 360) % 360 / 45) % 8;
  return POINTS[idx];
}
