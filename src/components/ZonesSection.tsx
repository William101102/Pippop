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
    if (!location) { setMessage('Turn on location before creating a Zenland'); return; }
    if (!label.trim()) { setMessage('Give this Zenland a name'); return; }
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
      <div className="eyebrow">My Zenlands</div>
      <p className="muted empty-hint">Name the places you go often — friends can see the name, and get notified when you arrive or leave.</p>

      {myZones.length > 0 && (
        <div className="friend-list">
          {myZones.map((zone) => (
            <div className="friend-row zone-row" key={zone.id}>
              <button type="button" className="zone-row-main" onClick={() => onFocus(zone.lat, zone.lng)}>
                <span className="avatar place-avatar">{zone.emoji}</span>
                <div><b>{zone.label}</b><small>Friends can see · {zone.radius_m}m radius</small></div>
              </button>
              <button type="button" className="zone-delete" onClick={() => onDelete(zone.id)} aria-label="Delete Zenland">
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
          <input value={label} maxLength={24} placeholder="e.g. Gym" onChange={(e) => setLabel(e.target.value)} />
          {message && <div className="form-message">{message}</div>}
          <div className="chip-row">
            <button type="button" className="chip" onClick={() => setOpen(false)} disabled={busy}>Cancel</button>
            <button type="button" className="primary compact wide" onClick={submit} disabled={busy}>
              {busy ? <Loader2 size={14} className="spin" /> : 'Create at current location'}
            </button>
          </div>
        </div>
      ) : (
        <button type="button" className="share-card-button" onClick={() => setOpen(true)}>
          <span>📍</span>
          <div><b>Create a Zenland</b><small>Using your current location</small></div>
        </button>
      )}
    </>
  );
}
