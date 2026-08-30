import { Bell, ChevronDown, Ghost } from 'lucide-react';
import type { GhostMode, Profile } from '../types';
import { initials } from '../lib/format';

interface Props {
  me: Profile;
  preview: boolean;
  ghostMode: GhostMode;
  onOpenWorld: () => void;
  onOpenSettings: () => void;
  onExitPreview: () => void;
  onNotify: (text: string) => void;
}

export function TopBar({ me, preview, ghostMode, onOpenWorld, onOpenSettings, onExitPreview, onNotify }: Props) {
  return (
    <header className="topbar">
      <button className="profile-chip" type="button" onClick={onOpenWorld}>
        <span style={{ background: me.avatar_color }}>{initials(me.display_name)}</span>
        <div><b>{me.display_name}</b><small>{me.status_emoji} {me.status_text}</small></div>
        <ChevronDown size={16} />
      </button>
      <div className="top-actions">
        {preview && <button className="demo-badge" type="button" onClick={onExitPreview}>预览模式 · 返回登录</button>}
        <button className="circle-button" type="button" onClick={() => onNotify('现在没有新通知')}><Bell size={20} /></button>
        <button className={`circle-button ${ghostMode !== 'precise' ? 'active' : ''}`} type="button" onClick={onOpenSettings}><Ghost size={21} /></button>
      </div>
    </header>
  );
}
