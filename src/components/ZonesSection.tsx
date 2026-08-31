import { useState } from 'react';
import { Loader2, Trash2 } from 'lucide-react';
import { ZONE_EMOJI } from '../services/zones';
import type { LiveLocation, Zone } from '../types';

interface Props {
  myZones: Zone[];
  location: LiveLocation | null;
  onCreate: (label: string, emoji: string, lat: number, lng: number) => Promise<{ error?: string }>;
  onDelete: (id: string) => void;
  onFocus: (lat: number, lng: number) => void;
}

/** "Zenlands": friend-visible, hand-named zones — unlike the private,
 *  auto-detected overnight places below them in the World panel. */
export function ZonesSection({ myZones, location, onCreate, onDelete, onFocus }: Props) {
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState('');
  const [emoji, setEmoji] = useState(ZONE_EMOJI[0]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  async function submit() {
    if (!location) { setMessage('需要先定位才能创建地标'); return; }
    if (!label.trim()) { setMessage('给地标起个名字吧'); return; }
    setBusy(true);
    setMessage('');
    const result = await onCreate(label, emoji, location.lat, location.lng);
    setBusy(false);
    if (result.error) { setMessage(result.error); return; }
    setLabel('');
    setOpen(false);
  }

  return (
    <>
      <div className="eyebrow">我的地标 · Zenlands</div>
      <p className="muted empty-hint">给常去的地方起个名字，好友能看到名字，你到达/离开时他们会收到通知。</p>

      {myZones.length > 0 && (
        <div className="friend-list">
          {myZones.map((zone) => (
            <div className="friend-row zone-row" key={zone.id}>
              <button type="button" className="zone-row-main" onClick={() => onFocus(zone.lat, zone.lng)}>
                <span className="avatar place-avatar">{zone.emoji}</span>
                <div><b>{zone.label}</b><small>好友可见 · 半径 {zone.radius_m} 米</small></div>
              </button>
              <button type="button" className="zone-delete" onClick={() => onDelete(zone.id)} aria-label="删除地标">
                <Trash2 size={15} />
              </button>
            </div>
          ))}
        </div>
      )}

      {open ? (
        <div className="zone-composer">
          <div className="chip-row tight">
            {ZONE_EMOJI.map((e) => (
              <button key={e} type="button" className={emoji === e ? 'chip selected' : 'chip'} onClick={() => setEmoji(e)}>{e}</button>
            ))}
          </div>
          <input value={label} maxLength={24} placeholder="例如：健身房" onChange={(e) => setLabel(e.target.value)} />
          {message && <div className="form-message">{message}</div>}
          <div className="chip-row">
            <button type="button" className="chip" onClick={() => setOpen(false)} disabled={busy}>取消</button>
            <button type="button" className="primary compact wide" onClick={submit} disabled={busy}>
              {busy ? <Loader2 size={14} className="spin" /> : '在当前位置创建'}
            </button>
          </div>
        </div>
      ) : (
        <button type="button" className="share-card-button" onClick={() => setOpen(true)}>
          <span>📍</span>
          <div><b>创建一个地标</b><small>用你当前的位置</small></div>
        </button>
      )}
    </>
  );
}
