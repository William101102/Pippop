import { useEffect, useState } from 'react';
import { Loader2, X } from 'lucide-react';
import { reverseGeocode } from '../services/checkins';
import type { LiveLocation, PlaceCategory, VisitVisibility } from '../types';

const CATEGORIES: { value: PlaceCategory; label: string; icon: string }[] = [
  { value: 'cafe', label: '咖啡', icon: '☕️' },
  { value: 'food', label: '吃饭', icon: '🍜' },
  { value: 'park', label: '公园', icon: '🌳' },
  { value: 'gym', label: '运动', icon: '🏋️' },
  { value: 'shop', label: '购物', icon: '🛍️' },
  { value: 'home', label: '家', icon: '🏠' },
  { value: 'work', label: '工作', icon: '💼' },
  { value: 'other', label: '其他', icon: '📍' },
];

const VISIBILITIES: { value: VisitVisibility; label: string; detail: string }[] = [
  { value: 'friends', label: '好友可见', detail: '朋友能在附近看到这次打卡' },
  { value: 'private', label: '仅自己', detail: '只出现在你的足迹里' },
];

interface Props {
  location: LiveLocation;
  onClose: () => void;
  onSubmit: (input: {
    name: string;
    category: PlaceCategory;
    address?: string | null;
    visibility: VisitVisibility;
    note?: string;
  }) => Promise<{ error?: string }>;
}

export function CheckInPanel({ location, onClose, onSubmit }: Props) {
  const [name, setName] = useState('');
  const [address, setAddress] = useState<string | null>(null);
  const [category, setCategory] = useState<PlaceCategory>('cafe');
  const [visibility, setVisibility] = useState<VisitVisibility>('friends');
  const [note, setNote] = useState('');
  const [resolving, setResolving] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    let cancelled = false;
    reverseGeocode(location.lat, location.lng).then((result) => {
      if (cancelled) return;
      if (result?.name) setName((current) => current || result.name!);
      if (result?.address) setAddress(result.address);
      setResolving(false);
    });
    return () => { cancelled = true; };
  }, [location.lat, location.lng]);

  async function submit() {
    setBusy(true);
    setMessage('');
    const result = await onSubmit({ name, category, address, visibility, note });
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">在这里打卡</div><h2>你在哪儿？</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <label className="checkin-field">
          地点名字
          <input
            value={name}
            maxLength={80}
            placeholder={resolving ? '正在识别附近地点…' : '例如：楼下那家咖啡'}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        {address && <p className="checkin-address">{resolving ? '' : address}</p>}
        {resolving && <p className="checkin-address"><Loader2 size={13} className="spin" /> 正在识别位置…</p>}

        <div className="eyebrow">类型</div>
        <div className="chip-row">
          {CATEGORIES.map((item) => (
            <button
              key={item.value}
              type="button"
              className={category === item.value ? 'chip selected' : 'chip'}
              onClick={() => setCategory(item.value)}
            >{item.icon} {item.label}</button>
          ))}
        </div>

        <label className="checkin-field">
          想说点什么（可选）
          <input value={note} maxLength={140} placeholder="这里的拿铁真不错" onChange={(e) => setNote(e.target.value)} />
        </label>

        <div className="eyebrow">谁能看到</div>
        {VISIBILITIES.map((item) => (
          <button
            key={item.value}
            type="button"
            className={`visibility-row ${visibility === item.value ? 'selected' : ''}`}
            onClick={() => setVisibility(item.value)}
          >
            <div><b>{item.label}</b><small>{item.detail}</small></div>
            <i />
          </button>
        ))}

        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" type="button" disabled={busy || !name.trim()} onClick={submit}>
          {busy ? '打卡中…' : '打卡 📍'}
        </button>
      </div>
    </aside>
  );
}
