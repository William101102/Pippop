import { Avatar } from './Avatar';
import type { Profile } from '../types';

interface Props {
  sender: Profile;
  emoji: string;
  label?: string;
}

/** Big celebratory popup for an incoming throw — separate from the plain text
 *  toast because landing a 🎂 on someone deserves more than a status line. */
export function GiftToast({ sender, emoji, label }: Props) {
  return (
    <div className="gift-toast" aria-live="polite">
      <div className="gift-toast-burst">{emoji}</div>
      <Avatar profile={sender} className="gift-toast-avatar" />
      <div className="gift-toast-text">
        <b>{sender.display_name}</b>
        <small>给你扔了个 {emoji}{label ? ` ${label}` : ''}</small>
      </div>
      <span className="gift-toast-spark s1">✨</span>
      <span className="gift-toast-spark s2">✨</span>
      <span className="gift-toast-spark s3">✨</span>
    </div>
  );
}
