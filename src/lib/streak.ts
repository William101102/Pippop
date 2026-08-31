export interface StreakInfo {
  /** 0 when the server value is stale (no interaction yesterday or today) —
   *  the DB only corrects streak_days on the next interaction, so the client
   *  treats anything older as already broken rather than showing a lie. */
  days: number;
  /** Interacted yesterday but not yet today — the streak dies at UTC midnight
   *  unless someone sends a message or throws something before then. */
  atRisk: boolean;
  icon: string;
  tier: '' | 'spark' | 'flame' | 'blaze' | 'legend';
}

const DAY_MS = 86_400_000;

/** Days between two UTC calendar dates (ignores time-of-day). */
function utcDayDiff(a: Date, b: Date) {
  const da = Date.UTC(a.getUTCFullYear(), a.getUTCMonth(), a.getUTCDate());
  const db = Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate());
  return Math.round((da - db) / DAY_MS);
}

export function streakInfo(streakDays: number | undefined, lastInteractionOn: string | null | undefined): StreakInfo {
  const days = streakDays ?? 0;
  if (!days || !lastInteractionOn) return { days: 0, atRisk: false, icon: '', tier: '' };
  const diff = utcDayDiff(new Date(), new Date(`${lastInteractionOn}T00:00:00Z`));
  // More than a day since the last interaction: the streak is dead, even if
  // the stored number has not been zeroed out yet (that only happens on the
  // next message/throw). Show the honest state instead.
  if (diff > 1) return { days: 0, atRisk: false, icon: '', tier: '' };
  const atRisk = diff === 1;
  const tier: StreakInfo['tier'] = days >= 30 ? 'legend' : days >= 14 ? 'blaze' : days >= 3 ? 'flame' : 'spark';
  const icon = tier === 'legend' ? '💯' : tier === 'blaze' ? '🔥' : tier === 'flame' ? '🔥' : '✨';
  return { days, atRisk, icon, tier };
}
