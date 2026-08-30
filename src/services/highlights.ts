import { supabase } from '../lib/supabase';
import type { Highlight } from '../types';

const MISSING_TABLE = '42P01';
const MAX_PHOTO_BYTES = 12 * 1024 * 1024;
const UPLOAD_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const PHOTO_MAX_DIM = 960;

/** Still-live highlights from me and my accepted friends, newest first,
 *  grouped by author. RLS already drops anyone who isn't a friend and
 *  anything past `expires_at`. */
export async function loadFriendHighlights(): Promise<Record<string, Highlight[]>> {
  const { data, error } = await supabase
    .from('highlights')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) {
    if (error.code === MISSING_TABLE) return {};
    throw error;
  }
  const byUser: Record<string, Highlight[]> = {};
  for (const row of (data || []) as Highlight[]) {
    (byUser[row.user_id] ??= []).push(row);
  }
  return byUser;
}

function looksLikeImage(file: File) {
  if (file.type.startsWith('image/')) return true;
  // iOS camera roll often sends HEIC with an empty type.
  return !file.type || /\.(jpe?g|png|webp|gif|heic|heif)$/i.test(file.name);
}

/** Downscales to a manageable JPEG so a full-res phone photo does not blow
 *  past the shared `avatars` bucket's size limit or take forever to upload. */
async function normalizeHighlightPhoto(file: File): Promise<{ body: Blob; contentType: string; extension: string }> {
  const fallback = () => {
    if (!UPLOAD_TYPES.has(file.type)) throw new Error('这张图片浏览器读不出来，换一张 JPG 或 PNG 试试');
    const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
    return { body: file as Blob, contentType: file.type, extension };
  };
  if (typeof createImageBitmap !== 'function') return fallback();

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    return fallback();
  }
  try {
    const scale = Math.min(1, PHOTO_MAX_DIM / Math.max(bitmap.width, bitmap.height));
    const w = Math.round(bitmap.width * scale);
    const h = Math.round(bitmap.height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return fallback();
    ctx.drawImage(bitmap, 0, 0, w, h);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.86));
    if (!blob) return fallback();
    return { body: blob, contentType: 'image/jpeg', extension: 'jpg' };
  } finally {
    bitmap.close();
  }
}

/** Reuses the `avatars` bucket: its storage policies already only check that
 *  the first path segment is the uploader's own uid, so any filename under
 *  that folder is fine — no new bucket/policy needed for this feature. */
export async function uploadHighlightPhoto(userId: string, file: File): Promise<string> {
  if (!looksLikeImage(file)) throw new Error('请选择一张图片');
  if (file.size > MAX_PHOTO_BYTES) throw new Error('图片不能超过 12 MB');
  const { body, contentType, extension } = await normalizeHighlightPhoto(file);
  const path = `${userId}/highlight-${Date.now()}.${extension}`;
  const { error } = await supabase.storage.from('avatars').upload(path, body, {
    cacheControl: '3600',
    contentType,
    upsert: false,
  });
  if (error) {
    if (/bucket not found/i.test(error.message)) throw new Error('存储还没建好：请先运行 backend/supabase/setup.sql');
    throw new Error(error.message || '照片上传失败，请稍后再试');
  }
  return supabase.storage.from('avatars').getPublicUrl(path).data.publicUrl;
}

export async function postHighlight(userId: string, body: string, mediaUrl: string | null) {
  const { error } = await supabase.from('highlights').insert({
    user_id: userId,
    body: body.trim(),
    media_url: mediaUrl,
  });
  if (error) {
    if (error.code === MISSING_TABLE) throw new Error('动态功能还没上线：请先运行 backend/supabase/setup.sql');
    throw error;
  }
}

export async function deleteHighlight(id: string) {
  const { error } = await supabase.from('highlights').delete().eq('id', id);
  if (error) throw error;
}
