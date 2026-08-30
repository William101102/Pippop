import { useRef, useState } from 'react';
import { Camera, Loader2, X } from 'lucide-react';

interface Props {
  onClose: () => void;
  onSubmit: (input: { body: string; file: File | null }) => Promise<{ error?: string }>;
}

/** 24 小时后自动消失, mirrors Zenly/Snap-style "highlights". A photo isn't
 *  required — a text-only highlight still shows up as a colored card. */
export function PostHighlightSheet({ onClose, onSubmit }: Props) {
  const [body, setBody] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  function pick(f: File | undefined) {
    if (!f) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
  }

  async function submit() {
    if (!file && !body.trim()) { setMessage('拍张照片或者写点什么吧'); return; }
    setBusy(true);
    setMessage('');
    const result = await onSubmit({ body, file });
    setBusy(false);
    if (result.error) setMessage(result.error);
  }

  return (
    <aside className="sheet sheet-full">
      <div className="sheet-head">
        <div><div className="eyebrow">分享给朋友</div><h2>发一条动态</h2></div>
        <button className="close-button" type="button" onClick={onClose}><X size={19} /></button>
      </div>

      <div className="checkin-body">
        <button type="button" className="highlight-photo-picker" onClick={() => inputRef.current?.click()}>
          {preview ? (
            <img src={preview} alt="" />
          ) : (
            <><Camera size={26} /><span>选一张照片（可选）</span></>
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
          想说点什么
          <input value={body} maxLength={140} placeholder="此刻在做什么？" onChange={(e) => setBody(e.target.value)} />
        </label>

        <p className="checkin-address">24 小时后自动消失，只有好友能看到</p>

        {message && <div className="form-message">{message}</div>}
        <button className="primary wide" type="button" disabled={busy} onClick={submit}>
          {busy ? <Loader2 size={16} className="spin" /> : '发布 ✨'}
        </button>
      </div>
    </aside>
  );
}
