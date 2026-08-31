import { useEffect, useState } from 'react';
import { BatteryCharging, MessageCircle, Send, Share2, SmilePlus, Sparkles, Star, X } from 'lucide-react';
import { Avatar } from './Avatar';
import { compassLabel, fmtDist, fmtSpeed, timeAgo } from '../lib/format';
import { bearingDeg, haversineKm } from '../lib/geo';
import { useDraggableSheet } from '../hooks/useDraggableSheet';
import { haptic } from '../lib/native';
import { THROWABLES } from '../services/social';
import { streakInfo } from '../lib/streak';
import type { Friend, LiveLocation } from '../types';

// Escalating milestones, mirroring Snapchat's own streak beats — big enough
// gaps that crossing one actually feels like an event.
const STREAK_MILESTONES = [3, 7, 14, 30, 50, 100, 200, 365];

interface Props {
  person: Friend;
  myLocation: LiveLocation | null;
  onClose: () => void;
  onChat: () => void;
  onWave: () => void | Promise<void>;
  onWhatsUp: () => void | Promise<void>;
  onShare: () => void | Promise<void>;
  onReact: (emoji: string) => void;
  onToggleBest: () => void;
  onSend: (text: string) => Promise<{ error?: string }>;
  onError: (text: string) => void;
}

export function PersonCard({
  person, myLocation, onClose, onChat, onWave, onWhatsUp, onShare,
  onReact, onToggleBest, onSend, onError,
}: Props) {
  const [draft, setDraft] = useState('');
  const [thrown, setThrown] = useState<{ emoji: string; key: number } | null>(null);
  const [milestone, setMilestone] = useState<number | null>(null);
  const drag = useDraggableSheet({ onDismiss: onClose, enabled: true, baseTransform: 'translateX(-50%)' });
  const streak = streakInfo(person.streak_days, person.last_interaction_on, person.streak_grace_value, person.streak_grace_days);

  // Fires once per device the first time a friend's streak is seen crossing a
  // milestone — a purely client-side "did you notice" nudge, no schema needed.
  useEffect(() => {
    const key = `pinpop-streak-seen-${person.id}`;
    let seen = 0;
    try { seen = Number(localStorage.getItem(key) || 0); } catch { /* private mode etc */ }
    const current = streak.days;
    const crossed = STREAK_MILESTONES.find((m) => current >= m && seen < m);
    if (crossed) {
      haptic('success');
      setMilestone(crossed);
      const t = window.setTimeout(() => setMilestone(null), 2800);
      try { localStorage.setItem(key, String(current)); } catch { /* ignore */ }
      return () => window.clearTimeout(t);
    }
    if (current !== seen) {
      try { localStorage.setItem(key, String(current)); } catch { /* ignore */ }
    }
  }, [person.id, streak.days]);

  function throwAt(emoji: string) {
    haptic('medium');
    setThrown({ emoji, key: Date.now() });
    window.setTimeout(() => setThrown(null), 900);
    onReact(emoji);
  }

  const theirs = person.location;
  const km = myLocation && theirs
    ? haversineKm(myLocation.lat, myLocation.lng, theirs.lat, theirs.lng)
    : null;
  const heading = myLocation && theirs
    ? bearingDeg(myLocation.lat, myLocation.lng, theirs.lat, theirs.lng)
    : null;
  const speed = fmtSpeed(theirs?.speed);
  const live = Boolean(theirs)
    && person.ghost_mode !== 'frozen'
    && Date.now() - new Date(theirs!.updated_at).getTime() < 30 * 60_000;

  async function submit() {
    const text = draft.trim();
    if (!text) return;
    haptic('light');
    const result = await onSend(text);
    if (result.error) onError(result.error);
    else { setDraft(''); onChat(); }
  }

  return (
    <section className={`person-card ${drag.sheetProps.className}`} style={drag.sheetProps.style}>
      <div className="grabber-hit" {...drag.handleProps}><div className="grabber" /></div>
      <button className="close-button" type="button" onClick={onClose}><X size={18} /></button>
      <button
        className={`best-friend-toggle ${person.is_best_friend ? 'on' : ''}`}
        type="button"
        onClick={onToggleBest}
        aria-label={person.is_best_friend ? 'Remove best friend' : 'Set as best friend'}
      >
        <Star size={17} />
      </button>

      <div className="person-card-body">
      <Avatar profile={person} className="big-avatar" showStatus />
      <h2>{person.display_name}</h2>
      <p>@{person.username} · {timeAgo(theirs?.updated_at)}</p>
      {streak.days > 0 && (
        <div className={`streak-badge ${streak.tier} ${streak.atRisk ? 'at-risk' : ''}`}>
          {streak.atRisk ? '⏳' : streak.icon} {streak.days}-day streak
          {streak.atRisk && <em>No interaction today yet — breaks at midnight</em>}
        </div>
      )}
      {streak.repairing && (
        <div className="streak-badge repairing">
          🩹 Repairing streak — {streak.repairDaysLeft} more day{streak.repairDaysLeft === 1 ? '' : 's'} in a row
          restores it to {streak.repairTarget}
        </div>
      )}
      {streak.canRepair && (
        <div className="streak-badge can-repair">
          💔 Missed yesterday — interact today to start repairing it back to {streak.repairTarget}
        </div>
      )}
      {milestone && (
        <div className="streak-milestone" aria-hidden="true">
          <span>🎉</span>
          <b>{milestone}-day streak!</b>
        </div>
      )}

      {km != null && heading != null ? (
        <div className="person-compass">
          <div className="compass-ring" style={{ ['--deg' as string]: `${heading}deg` }}>
            <i />
          </div>
          <div>
            <b>{fmtDist(km)}</b>
            <small>{compassLabel(heading)} · {live ? 'Live' : 'Last seen'}</small>
          </div>
          {speed && <em>{speed}</em>}
        </div>
      ) : null}

      <div className="presence">
        <span className={`pulse ${live ? '' : 'off'}`} />
        <b>{person.status_text}</b>
        {person.battery_level != null && (
          <small>{person.is_charging && <BatteryCharging size={12} />} {person.battery_level}%</small>
        )}
      </div>

      <div className="throw-section">
        <div className="eyebrow">Throw something to {person.display_name.slice(0, 6)}</div>
        <div className="throw-grid">
          {THROWABLES.map((t) => (
            <button key={t.emoji} type="button" className="throw-chip" onClick={() => throwAt(t.emoji)}>
              <span>{t.emoji}</span>
              <small>{t.label}</small>
            </button>
          ))}
        </div>
        {thrown && (
          <div key={thrown.key} className="throw-fx" aria-hidden="true">{thrown.emoji}</div>
        )}
      </div>

      <div className="person-actions">
        <button type="button" onClick={onWave}><SmilePlus /><span>Wave</span></button>
        <button type="button" onClick={onWhatsUp}><Sparkles /><span>What&apos;s Up</span></button>
        <button type="button" onClick={onChat}><MessageCircle /><span>Chat</span></button>
        <button type="button" onClick={onShare}><Share2 /><span>Share card</span></button>
      </div>

      <div className="quick-message">
        <input
          placeholder={`Message ${person.display_name}…`}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') void submit(); }}
        />
        <button type="button" onClick={() => void submit()}><Send size={18} /></button>
      </div>
      </div>
    </section>
  );
}
