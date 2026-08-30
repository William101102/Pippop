import { Footprints, MapPin, MessageCircle, Search, Users } from 'lucide-react';
import type { Panel } from '../types';

interface Props {
  panel: Panel;
  onChange: (panel: Panel) => void;
  onWaveAll: () => void;
}

export function BottomDock({ panel, onChange, onWaveAll }: Props) {
  return (
    <nav className="dock">
      <button type="button" className={panel === 'friends' ? 'active' : ''} onClick={() => onChange('friends')}><Users /><span>朋友</span></button>
      <button type="button" className={panel === 'places' ? 'active' : ''} onClick={() => onChange('places')}><Search /><span>探索</span></button>
      <button type="button" className="center-action" onClick={onWaveAll}><span>👋</span></button>
      <button type="button" className={panel === 'world' ? 'active' : ''} onClick={() => onChange('world')}><Footprints /><span>足迹</span></button>
      <button type="button" className={panel === 'messages' ? 'active' : ''} onClick={() => onChange('messages')}><MessageCircle /><span>消息</span></button>
    </nav>
  );
}
