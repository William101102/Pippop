import { supabase } from '../lib/supabase';
import type { Profile } from '../types';

const MAX_AVATAR_BYTES = 12 * 1024 * 1024;
const UPLOAD_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const AVATAR_SIZE = 512;

interface NormalizedAvatar {
  body: Blob;
  contentType: string;
  extension: string;
}

/**
 * Re-encodes the picked image to a square 512px JPEG. Phone cameras hand us
 * HEIC or 8 MB files that the bucket's mime/size rules reject, so normalising
 * first is what makes "pick any photo" actually work.
 */
async function normalizeAvatar(file: File): Promise<NormalizedAvatar> {
  const fallback = (): NormalizedAvatar => {
    if (!UPLOAD_TYPES.has(file.type)) {
      throw new Error('这张图片浏览器读不出来，换一张 JPG 或 PNG 试试');
    }
    const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
    return { body: file, contentType: file.type, extension };
  };

  if (typeof createImageBitmap !== 'function') return fallback();

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    return fallback();
  }

  try {
    const crop = Math.min(bitmap.width, bitmap.height);
    const canvas = document.createElement('canvas');
    canvas.width = AVATAR_SIZE;
    canvas.height = AVATAR_SIZE;
    const ctx = canvas.getContext('2d');
    if (!ctx) return fallback();
    ctx.drawImage(
      bitmap,
      (bitmap.width - crop) / 2, (bitmap.height - crop) / 2, crop, crop,
      0, 0, AVATAR_SIZE, AVATAR_SIZE,
    );
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.9));
    if (!blob) return fallback();
    return { body: blob, contentType: 'image/jpeg', extension: 'jpg' };
  } finally {
    bitmap.close();
  }
}

function describeUploadError(error: { message?: string; statusCode?: string }) {
  const message = error.message || '';
  if (/bucket not found/i.test(message)) {
    return '头像存储还没建好：请在 Supabase 里执行 202608300002_profile_avatars.sql';
  }
  if (/row-level security|policy/i.test(message)) {
    return '没有上传权限：请确认 202608300002_profile_avatars.sql 已执行';
  }
  if (/mime|content type/i.test(message)) {
    return '这个图片格式不被支持，换一张 JPG 或 PNG 试试';
  }
  if (/exceeded|too large|payload/i.test(message)) {
    return '图片太大了，换一张小一点的';
  }
  return message || '头像上传失败，请稍后再试';
}

function looksLikeImage(file: File) {
  if (file.type.startsWith('image/')) return true;
  // iOS camera roll often sends HEIC with an empty type.
  return !file.type || /\.(jpe?g|png|webp|gif|heic|heif)$/i.test(file.name);
}

export async function uploadProfileAvatar(userId: string, file: File): Promise<string> {
  if (!looksLikeImage(file)) throw new Error('请选择一张图片');
  if (file.size > MAX_AVATAR_BYTES) throw new Error('图片不能超过 12 MB');

  const { body, contentType, extension } = await normalizeAvatar(file);
  const path = `${userId}/avatar-${Date.now()}.${extension}`;
  const { error: uploadError } = await supabase.storage.from('avatars').upload(path, body, {
    cacheControl: '3600',
    contentType,
    upsert: true,
  });
  if (uploadError) throw new Error(describeUploadError(uploadError));

  const { data } = supabase.storage.from('avatars').getPublicUrl(path);
  const avatarUrl = data.publicUrl;
  const { error: updateError } = await supabase.from('profiles').update({ avatar_url: avatarUrl }).eq('id', userId);
  if (updateError) {
    await supabase.storage.from('avatars').remove([path]).catch(() => undefined);
    throw new Error(updateError.message || '头像已上传但没能保存到资料');
  }
  return avatarUrl;
}

export async function updateProfile(userId: string, changes: Partial<Pick<Profile, 'display_name' | 'status_emoji' | 'status_text'>>) {
  const { error } = await supabase.from('profiles').update(changes).eq('id', userId);
  if (error) throw error;
}
