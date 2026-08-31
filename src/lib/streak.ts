export interface StreakInfo {
  /** 0 when the server value is stale (no interaction yesterday or today) —
   *  the DB only corrects streak_days on the next interaction, so the client
   *  treats anything older as already broken rather than showing a lie. */
  days: number;
  /** Interacted yesterday but not yet today — the streak dies at UTC midnight
   *  unless someone sends a message or throws something before then. */
  atRisk: boolean;
  /** Missed exactly one day, and today is still the last chance to start the
   *  three-day repair window (see repairing below) before it's gone for good. */
  canRepair: boolean;
  /** A repair is already underway (streak_grace_value is set server-side). */
  repairing: boolean;
  /** How many more consecutive days are needed to finish the repair. */
  repairDaysLeft: number;
  /** What the streak becomes once the repair completes. */
  repairTarget: number;
  icon: string;
  tier: '' | 'spark' | 'flame' | 'blaze' | 'legend';
}

const DAY_MS = 86_400_000;
const DEAD: StreakInfo = { days: 0, atRisk: false, canRepair: false, repairing: false, repairDaysLeft: 0, repairTarget: 0, icon: '', tier: '' };

/** Days between two UTC calendar dates (ignores time-of-day). */
function utcDayDiff(a: Date, b: Date) {
  const da = Date.UTC(a.getUTCFullYear(), a.getUTCMonth(), a.getUTCDate());
  const db = Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate());
  return Math.round((da - db) / DAY_MS);
}

function tierFor(days: number): { tier: StreakInfo['tier']; icon: string } {
  const tier: StreakInfo['tier'] = days >= 30 ? 'legend' : days >= 14 ? 'blaze' : days >= 3 ? 'flame' : 'spark';
  const icon = tier === 'legend' ? '💯' : '🔥';
  return { tier, icon: days >= 3 ? icon : '✨' };
}

export function streakInfo(
  streakDays: number | undefined,
  lastInteractionOn: string | null | undefined,
  graceValue?: number | null,
  graceDays?: number,
): StreakInfo {
  // A repair already in progress overrides everything else — bump_friend_streak
  // only sets this once the pair has actually come back after a miss.
  if (graceValue != null && (graceDays ?? 0) > 0) {
    const left = Math.max(0, 3 - (graceDays ?? 0));
    return {
      ...DEAD,
      repairing: true,
      repairDaysLeft: left,
      repairTarget: graceValue + 3,
      icon: '🩹',
    };
  }

  const days = streakDays ?? 0;
  if (!days || !lastInteractionOn) return DEAD;
  const diff = utcDayDiff(new Date(), new Date(`${lastInteractionOn}T00:00:00Z`));
  if (diff === 2) {
    // Exactly one day missed, repair not started yet: today is the last
    // chance to trigger the window (see bump_friend_streak's gap === 2 case).
    return { ...DEAD, canRepair: true, repairTarget: days + 3, icon: '💔' };
  }
  // More than a day since the last interaction: the streak is dead, even if
  // the stored number has not been zeroed out yet (that only happens on the
  // next message/throw). Show the honest state instead.
  if (diff > 1) return DEAD;
  const atRisk = diff === 1;
  const { tier, icon } = tierFor(days);
  return { ...DEAD, days, atRisk, icon, tier };
}
