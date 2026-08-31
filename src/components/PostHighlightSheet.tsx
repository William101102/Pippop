import { useRef, useState } from 'react';
import { Camera, Loader2, MapPin, X } from 'lucide-react';
import type { LiveLocation } from '../types';

interface Props {
  location: LiveLocation | null;
  onClose: () => void;
  onSubmit: (input: { body: string; file: File | null; attachLocation: boolean }) => Promise<{ error?: string }>;
}

/** Auto-expires after 24 hours, mirrors Zenly/Snap-style "highlights". A photo isn't
 *  required — a text-only highlight still shows up as a colored card.
 *  Attaching a location is opt-in and off by default, same privacy-first
 *  instinct as Ghost Mode: a story pin on the map is a bigger disclosure
 *  than a story in the friend rail. */
export function PostHighlightSheet({ location, onClose, onSubmit }: Props) {
  const [body, setBody] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [attachLocation, setAttachLocation] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  function pick(f: File | undefined) {
    if (!f) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
  }

  async function submit() {
    if (!file && !body.trim()) { setMessage('Take a photo or write something'); return; }
    setBusy(true);
    setMessage('');
    const result = await onSubmit({ body, file, attachLocation: attachLocation && Boolean(location) });
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">Share with friends</div><h2>Post a story</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <button type="button" className="highlight-photo-picker" onClick={() => inputRef.current?.click()}>
          {preview ? (
            <img src={preview} alt="" />
          ) : (
            <><Camera size={26} /><span>Choose a photo (optional)</span></>
          )}
        </button>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => { pick(e.target.files?.[0]); e.target.value = ''; }}
        />

        <label className="checkin-field">
          Say something
          <input value={body} maxLength={140} placeholder="What are you up to?" onChange={(e) => setBody(e.target.value)} />
        </label>

        <button
          type="button"
          className={`location-toggle ${attachLocation ? 'on' : ''}`}
          disabled={!location}
          onClick={() => setAttachLocation((v) => !v)}
        >
          <MapPin size={16} />
          <div>
            <b>Attach my location</b>
            <small>{location ? 'Friends will see where this story was taken on the map' : 'No location right now, can\'t attach it'}</small>
          </div>
          <i className={`toggle-dot ${attachLocation ? 'on' : ''}`} />
        </button>

        <p className="checkin-address">Disappears after 24 hours, visible to friends only</p>

        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" type="button" disabled={busy} onClick={submit}>
          {busy ? <Loader2 size={16} className="spin" /> : 'Post ✨'}
        </button>
      </div>
    </aside>
  );
}
