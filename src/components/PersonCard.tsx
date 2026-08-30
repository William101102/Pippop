import { MessageCircle, Send, SmilePlus, X } from 'lucide-react';
import { friendShareText, shareText } from '../lib/geo';
import { timeAgo, initials } from '../lib/format';
import type { Friend, Profile } from '../types';

interface Props {
  person: Friend;
  onClose: () => void;
  onChat: () => void;
  onWave: () => void;
  onNotify: (text: string) => void;
}

export function PersonCard({ person, onClose, onChat, onWave, onNotify }: Props) {
  async function shareFriend() {
    const text = friendShareText(person.username, person.display_name);
    const result = await shareText('Pinpop 推荐好友', text, text.split('\n').pop() || '');
    onNotify(result === 'shared' ? `已分享 ${person.display_name}` : '已复制，发给其他好友吧！');
  }

  return (
    <section className="person-card">
      <button className="close-button" type="button" onClick={onClose}><X size={18} /></button>
      <span className="big-avatar" style={{ background: person.avatar_color }}>{initials(person.display_name)}<i>{person.status_emoji}</i></span>
      <h2>{person.display_name}</h2>
      <p>@{person.username} · {timeAgo(person.location?.updated_at)}</p>
      <div className="presence"><span className="pulse" /><b>{person.status_text}</b></div>
      <div className="person-actions">
        <button type="button" onClick={onWave}><SmilePlus /><span>打招呼</span></button>
        <button type="button" onClick={shareFriend}><Send /><span>分享</span></button>
        <button type="button" onClick={onChat}><MessageCircle /><span>聊天</span></button>
      </div>
      <div className="lock-note">🔒 只有好友能看到位置</div>
    </section>
  );
}

interface MeCardProps {
  me: Profile;
  onClose: () => void;
  onAddFriend: () => void;
  onCycleStatus: () => void;
  onShareSelf: () => void;
  onLogout: () => void;
}

export function MeCard({ me, onClose, onAddFriend, onCycleStatus, onShareSelf, onLogout }: MeCardProps) {
  return (
    <section className="person-card">
      <button className="close-button" type="button" onClick={onClose}><X size={18} /></button>
      <span className="big-avatar" style={{ background: me.avatar_color }}>{initials(me.display_name)}<i>{me.status_emoji}</i></span>
      <h2>{me.display_name}</h2>
      <p>{me.status_emoji} {me.status_text} · @{me.username}</p>
      <div className="person-actions">
        <button type="button" onClick={onAddFriend}><MessageCircle /><span>加好友</span></button>
        <button type="button" onClick={onCycleStatus}><SmilePlus /><span>换状态</span></button>
      </div>
      <button className="text-button" type="button" onClick={onShareSelf}>分享给朋友 →</button>
      <button className="text-button" type="button" onClick={onLogout}>退出登录</button>
      <div className="lock-note">🔒 只有好友能看到你的位置</div>
    </section>
  );
}
