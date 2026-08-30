import { Ghost } from 'lucide-react';
import { GHOST_MODES } from '../lib/constants';
import type { GhostMode } from '../types';

interface Props {
  mode: GhostMode;
  onChange: (mode: GhostMode) => void;
  onNotify: (text: string) => void;
}

export function GhostModePanel({ mode, onChange, onNotify }: Props) {
  return (
    <div className="ghost-panel">
      <p>选择朋友在地图上看到你的位置精度。服务端会按此模式返回坐标，不只是隐藏 UI。</p>
      {GHOST_MODES.map((m) => (
        <button key={m.value} type="button" className={mode === m.value ? 'selected' : ''} onClick={() => { onChange(m.value); onNotify(`已切换为${m.title}`); }}>
          <span>{m.icon}</span><div><b>{m.title}</b><small>{m.detail}</small></div><i />
        </button>
      ))}
      <div className="setting-row"><div><b>针对单个好友设置</b><small>为不同朋友选择不同模式</small></div><span>即将开放</span></div>
      <div className="privacy-note"><Ghost size={19} /><div><b>模糊/冻结由数据库视图强制执行</b><small>需先在开发 Supabase 项目应用迁移</small></div></div>
    </div>
  );
}
