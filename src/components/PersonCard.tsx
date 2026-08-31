import { useState } from 'react';
import { BatteryCharging, MessageCircle, Send, Share2, SmilePlus, Sparkles, Star, X } from 'lucide-react';
import { Avatar } from './Avatar';
import { compassLabel, fmtDist, fmtSpeed, timeAgo } from '../lib/format';
import { bearingDeg, haversineKm } from '../lib/geo';
import { useDraggableSheet } from '../hooks/useDraggableSheet';
import { haptic } from '../lib/native';
import { THROWABLES } from '../services/social';
import type { Friend, LiveLocation } from '../types';

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
  const drag = useDraggableSheet({ onDismiss: onClose, enabled: true });

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
        aria-label={person.is_best_friend ? '取消置顶好友' : '设为置顶好友'}
      >
        <Star size={17} />
      </button>

      <Avatar profile={person} className="big-avatar" showStatus />
      <h2>{person.display_name}</h2>
      <p>@{person.username} · {timeAgo(theirs?.updated_at)}</p>
      {(person.streak_days ?? 0) > 0 && (
        <div className="streak-badge">🔥 连续互动 {person.streak_days} 天</div>
      )}

      {km != null && heading != null ? (
        <div className="person-compass">
          <div className="compass-ring" style={{ ['--deg' as string]: `${heading}deg` }}>
            <i />
          </div>
          <div>
            <b>{fmtDist(km)}</b>
            <small>{compassLabel(heading)} · {live ? '实时' : '最后位置'}</small>
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
        <div className="eyebrow">扔一个给 {person.display_name.slice(0, 6)}</div>
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
        <button type="button" onClick={onWave}><SmilePlus /><span>打招呼</span></button>
        <button type="button" onClick={onWhatsUp}><Sparkles /><span>What&apos;s Up</span></button>
        <button type="button" onClick={onChat}><MessageCircle /><span>聊天</span></button>
        <button type="button" onClick={onShare}><Share2 /><span>分享名片</span></button>
      </div>

      <div className="quick-message">
        <input
          placeholder={`给 ${person.display_name} 发消息…`}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') void submit(); }}
        />
        <button type="button" onClick={() => void submit()}><Send size={18} /></button>
      </div>
    </section>
  );
}
