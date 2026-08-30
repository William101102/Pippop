import { supabase } from '../lib/supabase';
import type { Message } from '../types';

export async function loadThread(meId: string, friendId: string) {
  const { data, error } = await supabase
    .from('messages')
    .select('*')
    .or(`and(sender_id.eq.${meId},recipient_id.eq.${friendId}),and(sender_id.eq.${friendId},recipient_id.eq.${meId})`)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return (data || []) as Message[];
}

export async function sendMessage(senderId: string, recipientId: string, body: string) {
  const text = body.trim();
  if (!text) return { error: '消息不能为空' };
  const { error } = await supabase.from('messages').insert({ sender_id: senderId, recipient_id: recipientId, body: text });
  if (error) return { error: error.message };
  return {};
}

export async function sendWave(senderId: string, recipientId: string) {
  return sendMessage(senderId, recipientId, '👋');
}
