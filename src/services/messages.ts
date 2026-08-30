import { supabase } from '../lib/supabase';
import type { Message, MessageKind } from '../types';

export async function loadThread(meId: string, friendId: string) {
  const { data, error } = await supabase
    .from('messages')
    .select('*')
    .or(`and(sender_id.eq.${meId},recipient_id.eq.${friendId}),and(sender_id.eq.${friendId},recipient_id.eq.${meId})`)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return (data || []) as Message[];
}

export async function sendMessage(senderId: string, recipientId: string, body: string, kind: MessageKind = 'text') {
  const text = body.trim();
  if (!text) return { error: '消息不能为空' };
  if (text.length > 2000) return { error: '消息太长了，最多 2000 字' };
  const { error } = await supabase
    .from('messages')
    .insert({ sender_id: senderId, recipient_id: recipientId, body: text, kind });
  if (error) return { error: error.message };
  return {};
}

export async function sendWave(senderId: string, recipientId: string) {
  return sendMessage(senderId, recipientId, '👋', 'wave');
}

export async function waveAtEveryone(senderId: string, friendIds: string[]) {
  const results = await Promise.all(friendIds.map((id) => sendWave(senderId, id)));
  const failed = results.filter((r) => r.error).length;
  return { sent: results.length - failed, failed };
}

/**
 * "What's Up" pokes a friend to share what they are doing. The request row
 * drives the friend's prompt, the message keeps it visible in the thread.
 */
export async function sendWhatsUp(senderId: string, recipientId: string) {
  const { error } = await supabase
    .from('whats_up_requests')
    .insert({ sender_id: senderId, recipient_id: recipientId });
  // 42P01 = table missing (migration not applied yet); the message still works.
  if (error && error.code !== '42P01') return { error: error.message };
  return sendMessage(senderId, recipientId, "👀 What's Up？在干什么呀", 'whats_up');
}

export async function markThreadRead(meId: string, friendId: string) {
  const { error } = await supabase
    .from('messages')
    .update({ read_at: new Date().toISOString() })
    .eq('recipient_id', meId)
    .eq('sender_id', friendId)
    .is('read_at', null);
  if (error) throw error;
}

/** Unread message count keyed by the friend who sent them. */
export async function loadUnreadCounts(meId: string): Promise<Record<string, number>> {
  const { data, error } = await supabase
    .from('messages')
    .select('sender_id')
    .eq('recipient_id', meId)
    .is('read_at', null);
  if (error) throw error;
  const counts: Record<string, number> = {};
  for (const row of data || []) {
    const sender = (row as { sender_id: string }).sender_id;
    counts[sender] = (counts[sender] || 0) + 1;
  }
  return counts;
}
