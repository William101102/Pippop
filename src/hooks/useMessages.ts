import { useCallback, useState } from 'react';
import { loadThread, sendMessage, sendWave } from '../services/messages';
import type { Message } from '../types';

export function useMessages(meId: string | undefined) {
  const [threads, setThreads] = useState<Record<string, Message[]>>({});
  const [chatWith, setChatWith] = useState<string | null>(null);

  const openChat = useCallback(async (friendId: string) => {
    setChatWith(friendId);
    if (!meId) return;
    const rows = await loadThread(meId, friendId);
    setThreads((prev) => ({ ...prev, [friendId]: rows }));
  }, [meId]);

  const closeChat = useCallback(() => setChatWith(null), []);

  const reloadThread = useCallback(async (friendId: string) => {
    if (!meId) return;
    const rows = await loadThread(meId, friendId);
    setThreads((prev) => ({ ...prev, [friendId]: rows }));
  }, [meId]);

  const send = useCallback(async (friendId: string, body: string) => {
    if (!meId) return { error: '未登录' };
    const result = await sendMessage(meId, friendId, body);
    if (!result.error) await reloadThread(friendId);
    return result;
  }, [meId, reloadThread]);

  const wave = useCallback(async (friendId: string) => {
    if (!meId) return;
    await sendWave(meId, friendId);
    await reloadThread(friendId);
  }, [meId, reloadThread]);

  const pushIncoming = useCallback((msg: Message) => {
    if (!meId) return;
    const friendId = msg.sender_id === meId ? msg.recipient_id : msg.sender_id;
    setThreads((prev) => {
      const existing = prev[friendId] || [];
      if (existing.some((m) => m.id === msg.id)) return prev;
      return { ...prev, [friendId]: [...existing, msg] };
    });
  }, [meId]);

  return { threads, chatWith, openChat, closeChat, reloadThread, send, wave, pushIncoming };
}
