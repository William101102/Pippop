import { supabase } from '../lib/supabase';
import type { ChatGroup, Message, Profile } from '../types';

const MISSING_TABLE = '42P01';

/** Groups I belong to, each with its member profiles attached — RLS on
 *  chat_groups already limits this to groups `is_group_member()` allows. */
export async function loadMyGroups(): Promise<ChatGroup[]> {
  const { data: groups, error } = await supabase
    .from('chat_groups')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) {
    if (error.code === MISSING_TABLE) return [];
    throw error;
  }
  const rows = (groups || []) as { id: string; name: string; owner_id: string; created_at: string }[];
  if (!rows.length) return [];

  const { data: memberRows, error: memberError } = await supabase
    .from('chat_group_members')
    .select('group_id,user_id')
    .in('group_id', rows.map((g) => g.id));
  if (memberError) throw memberError;

  const memberIds = [...new Set((memberRows || []).map((r) => (r as { user_id: string }).user_id))];
  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .in('id', memberIds);
  if (profileError) throw profileError;
  const profileById = new Map((profiles || []).map((p) => [(p as Profile).id, p as Profile]));

  return rows.map((g) => ({
    ...g,
    members: (memberRows || [])
      .filter((r) => (r as { group_id: string }).group_id === g.id)
      .map((r) => profileById.get((r as { user_id: string }).user_id))
      .filter((p): p is Profile => Boolean(p)),
  }));
}

export async function createGroup(ownerId: string, name: string, memberIds: string[]) {
  const { data: group, error } = await supabase
    .from('chat_groups')
    .insert({ name: name.trim(), owner_id: ownerId })
    .select('*')
    .single();
  if (error) {
    if (error.code === MISSING_TABLE) throw new Error('群聊功能还没上线：请先运行 backend/supabase/setup.sql');
    throw error;
  }
  const allIds = [...new Set([ownerId, ...memberIds])];
  const { error: memberError } = await supabase
    .from('chat_group_members')
    .insert(allIds.map((userId) => ({ group_id: group.id, user_id: userId })));
  if (memberError) throw memberError;
  return group as { id: string; name: string; owner_id: string; created_at: string };
}

export async function loadGroupThread(groupId: string): Promise<Message[]> {
  const { data, error } = await supabase
    .from('messages')
    .select('*')
    .eq('group_id', groupId)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return (data || []) as Message[];
}

export async function sendGroupMessage(senderId: string, groupId: string, body: string) {
  const text = body.trim();
  if (!text) return { error: '消息不能为空' };
  if (text.length > 2000) return { error: '消息太长了，最多 2000 字' };
  const { error } = await supabase
    .from('messages')
    .insert({ sender_id: senderId, group_id: groupId, body: text, kind: 'text' });
  if (error) return { error: error.message };
  return {};
}
