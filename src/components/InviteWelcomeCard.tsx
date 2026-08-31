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
        <h2>You and {friend.display_name} are now friends</h2>
        <p>You can now see each other on the map — start your first streak day 🔥</p>
        <button className="primary wide" type="button" onClick={onOpenChat}>Say hi</button>
      </div>
    </section>
  );
}
