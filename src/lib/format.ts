export function esc(s: string) {
  return String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!,
  );
}

export function initials(name: string) {
  return name.trim().slice(0, 1).toUpperCase();
}

export function timeAgo(iso?: string) {
  if (!iso) return 'No location yet';
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
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

const POINTS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'] as const;

export function compassLabel(deg: number) {
  const idx = Math.round(((deg % 360) + 360) % 360 / 45) % 8;
  return POINTS[idx];
}
