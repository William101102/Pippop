import { useEffect, useState } from 'react';
import { Loader2, X } from 'lucide-react';
import { reverseGeocode } from '../services/checkins';
import type { LiveLocation, PlaceCategory, VisitVisibility } from '../types';

const CATEGORIES: { value: PlaceCategory; label: string; icon: string }[] = [
  { value: 'cafe', label: 'Cafe', icon: '☕️' },
  { value: 'food', label: 'Food', icon: '🍜' },
  { value: 'park', label: 'Park', icon: '🌳' },
  { value: 'gym', label: 'Gym', icon: '🏋️' },
  { value: 'shop', label: 'Shopping', icon: '🛍️' },
  { value: 'home', label: 'Home', icon: '🏠' },
  { value: 'work', label: 'Work', icon: '💼' },
  { value: 'other', label: 'Other', icon: '📍' },
];

const VISIBILITIES: { value: VisitVisibility; label: string; detail: string }[] = [
  { value: 'friends', label: 'Friends can see', detail: 'Friends can see this check-in nearby' },
  { value: 'private', label: 'Only me', detail: 'Only shows up in your own footprints' },
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
        <div><div className="eyebrow">Check in here</div><h2>Where are you?</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <label className="checkin-field">
          Place name
          <input
            value={name}
            maxLength={80}
            placeholder={resolving ? 'Finding nearby places…' : 'e.g. the cafe downstairs'}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        {address && <p className="checkin-address">{resolving ? '' : address}</p>}
        {resolving && <p className="checkin-address"><Loader2 size={13} className="spin" /> Finding your location…</p>}

        <div className="eyebrow">Category</div>
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
          Say something (optional)
          <input value={note} maxLength={140} placeholder="The latte here is great" onChange={(e) => setNote(e.target.value)} />
        </label>

        <div className="eyebrow">Who can see this</div>
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
          {busy ? 'Checking in…' : 'Check in 📍'}
        </button>
      </div>
    </aside>
  );
}
