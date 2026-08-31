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
      throw new Error('This browser can\'t read that image — try a JPG or PNG instead');
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
    return 'Avatar storage isn\'t set up yet — run 202608300002_profile_avatars.sql in Supabase';
  }
  if (/row-level security|policy/i.test(message)) {
    return 'No upload permission — make sure 202608300002_profile_avatars.sql has been run';
  }
  if (/mime|content type/i.test(message)) {
    return 'That image format isn\'t supported — try a JPG or PNG instead';
  }
  if (/exceeded|too large|payload/i.test(message)) {
    return 'That image is too large — try a smaller one';
  }
  return message || 'Avatar upload failed — please try again later';
}

function looksLikeImage(file: File) {
  if (file.type.startsWith('image/')) return true;
  // iOS camera roll often sends HEIC with an empty type.
  return !file.type || /\.(jpe?g|png|webp|gif|heic|heif)$/i.test(file.name);
}

export async function uploadProfileAvatar(userId: string, file: File): Promise<string> {
  if (!looksLikeImage(file)) throw new Error('Please choose an image');
  if (file.size > MAX_AVATAR_BYTES) throw new Error('Image can\'t exceed 12 MB');

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
    throw new Error(updateError.message || 'Avatar uploaded but couldn\'t be saved to your profile');
  }
  return avatarUrl;
}

export async function updateProfile(userId: string, changes: Partial<Pick<Profile, 'display_name' | 'status_emoji' | 'status_text'>>) {
  const { error } = await supabase.from('profiles').update(changes).eq('id', userId);
  if (error) throw error;
}
