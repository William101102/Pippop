import { PartyPopper, X } from 'lucide-react';
import { Avatar } from './Avatar';
import type { Profile } from '../types';

interface Props {
  friend: Profile;
  onClose: () => void;
  onOpenChat: () => void;
}

/** Shown the instant an invite-link redeem lands you a new friend — no
 *  separate approval step, so this card *is* the "you're connected" moment
 *  Zenly-style apps live or die on. */
export function InviteWelcomeCard({ friend, onClose, onOpenChat }: Props) {
  return (
    <section className="invite-welcome-backdrop" onClick={onClose}>
      <div className="invite-welcome-card" onClick={(e) => e.stopPropagation()}>
        <button className="close-button" type="button" onClick={onClose}><X size={18} /></button>
        <div className="invite-welcome-icon"><PartyPopper size={22} /></div>
        <Avatar profile={friend} className="big-avatar" />
        <h2>你和 {friend.display_name} 成为好友啦</h2>
        <p>现在可以在地图上看到彼此，开始你们的第一天连续互动吧 🔥</p>
        <button className="primary wide" type="button" onClick={onOpenChat}>打个招呼</button>
      </div>
    </section>
  );
}
