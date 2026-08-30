import { useState } from 'react';
import { Trash2, X } from 'lucide-react';
import { Avatar } from './Avatar';
import type { Highlight, Profile } from '../types';

interface Props {
  author: Profile;
  isMine: boolean;
  highlights: Highlight[];
  onClose: () => void;
  onDelete: (id: string) => void;
}

function ago(iso: string) {
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return '刚刚';
  if (mins < 60) return `${mins} 分钟前`;
  return `${Math.floor(mins / 60)} 小时前`;
}

export function HighlightViewer({ author, isMine, highlights, onClose, onDelete }: Props) {
  const [index, setIndex] = useState(0);
  const current = highlights[index];
  if (!current) return null;

  function step(delta: number) {
    const next = index + delta;
    if (next < 0) return;
    if (next >= highlights.length) { onClose(); return; }
    setIndex(next);
  }

  return (
    <div className="highlight-viewer-backdrop" onClick={onClose}>
      <div className="highlight-viewer" onClick={(e) => e.stopPropagation()}>
        <div className="highlight-progress">
          {highlights.map((h, i) => (
            <i key={h.id} className={i < index ? 'done' : i === index ? 'active' : ''} />
          ))}
        </div>
        <div className="highlight-viewer-head">
          <Avatar profile={author} />
          <div><b>{author.display_name}</b><small>{ago(current.created_at)}</small></div>
          {isMine && (
            <button type="button" className="highlight-delete" onClick={() => onDelete(current.id)} aria-label="删除动态">
              <Trash2 size={16} />
            </button>
          )}
          <button type="button" className="highlight-close" onClick={onClose} aria-label="关闭"><X size={20} /></button>
        </div>

        <div className="highlight-media">
          {current.media_url ? (
            <img src={current.media_url} alt="" />
          ) : (
            <div className="highlight-media-fallback">{current.body || '✨'}</div>
          )}
          <button type="button" className="highlight-tap-zone left" aria-label="上一条" onClick={() => step(-1)} />
          <button type="button" className="highlight-tap-zone right" aria-label="下一条" onClick={() => step(1)} />
        </div>
        {current.media_url && current.body && <p className="highlight-caption">{current.body}</p>}
      </div>
    </div>
  );
}
