import { supabase } from '../lib/supabase';
import type { Profile } from '../types';

const MAX_AVATAR_BYTES = 5 * 1024 * 1024;
const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export async function uploadProfileAvatar(userId: string, file: File): Promise<string> {
  if (!ALLOWED_TYPES.has(file.type)) throw new Error('请选择 JPG、PNG 或 WebP 图片');
  if (file.size > MAX_AVATAR_BYTES) throw new Error('头像不能超过 5 MB');

  const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
  const path = `${userId}/avatar-${Date.now()}.${extension}`;
  const { error: uploadError } = await supabase.storage.from('avatars').upload(path, file, {
    cacheControl: '3600',
    contentType: file.type,
    upsert: false,
  });
  if (uploadError) throw uploadError;

  const { data } = supabase.storage.from('avatars').getPublicUrl(path);
  const avatarUrl = data.publicUrl;
  const { error: updateError } = await supabase.from('profiles').update({ avatar_url: avatarUrl }).eq('id', userId);
  if (updateError) {
    await supabase.storage.from('avatars').remove([path]);
    throw updateError;
  }
  return avatarUrl;
}

export async function updateProfile(userId: string, changes: Partial<Pick<Profile, 'display_name' | 'status_emoji' | 'status_text'>>) {
  const { error } = await supabase.from('profiles').update(changes).eq('id', userId);
  if (error) throw error;
}
