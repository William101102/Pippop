import { useCallback, useEffect, useState } from 'react';
import {
  loadThread,
  loadUnreadCounts,
  markThreadRead,
  sendMessage,
  sendWave,
  sendWhatsUp,
  waveAtEveryone,
} from '../services/messages';
import type { Message } from '../types';

export function useMessages(meId: string | undefined) {
  const [threads, setThreads] = useState<Record<string, Message[]>>({});
  const [unread, setUnread] = useState<Record<string, number>>({});
  const [chatWith, setChatWith] = useState<string | null>(null);

  const refreshUnread = useCallback(async () => {
    if (!meId) return;
    try {
      setUnread(await loadUnreadCounts(meId));
    } catch {
      // badge counts are best-effort
    }
  }, [meId]);

  useEffect(() => {
    if (!meId) {
      setThreads({});
      setUnread({});
      setChatWith(null);
      return;
    }
    refreshUnread();
  }, [meId, refreshUnread]);

  const reloadThread = useCallback(async (friendId: string) => {
    if (!meId) return;
    const rows = await loadThread(meId, friendId);
    setThreads((prev) => ({ ...prev, [friendId]: rows }));
  }, [meId]);

  const openChat = useCallback(async (friendId: string) => {
    setChatWith(friendId);
    if (!meId) return;
    await reloadThread(friendId).catch(() => undefined);
    try {
      await markThreadRead(meId, friendId);
      setUnread((prev) => ({ ...prev, [friendId]: 0 }));
    } catch {
      // read receipts are best-effort
    }
  }, [meId, reloadThread]);

  const closeChat = useCallback(() => setChatWith(null), []);

  const send = useCallback(async (friendId: string, body: string) => {
    if (!meId) return { error: '未登录' };
    const result = await sendMessage(meId, friendId, body);
    if (!result.error) await reloadThread(friendId).catch(() => undefined);
    return result;
  }, [meId, reloadThread]);

  const wave = useCallback(async (friendId: string) => {
    if (!meId) return { error: '未登录' };
    const result = await sendWave(meId, friendId);
    if (!result.error) await reloadThread(friendId).catch(() => undefined);
    return result;
  }, [meId, reloadThread]);

  const waveAll = useCallback(async (friendIds: string[]) => {
    if (!meId) return { sent: 0, failed: 0 };
    const result = await waveAtEveryone(meId, friendIds);
    await Promise.all(friendIds.map((id) => reloadThread(id).catch(() => undefined)));
    return result;
  }, [meId, reloadThread]);

  const whatsUp = useCallback(async (friendId: string) => {
    if (!meId) return { error: '未登录' };
    const result = await sendWhatsUp(meId, friendId);
    if (!result.error) await reloadThread(friendId).catch(() => undefined);
    return result;
  }, [meId, reloadThread]);

  const pushIncoming = useCallback((msg: Message) => {
    if (!meId) return;
    if (msg.sender_id !== meId && msg.recipient_id !== meId) return;
    const friendId = msg.sender_id === meId ? msg.recipient_id : msg.sender_id;
    setThreads((prev) => {
      const existing = prev[friendId] || [];
      if (existing.some((m) => m.id === msg.id)) return prev;
      return { ...prev, [friendId]: [...existing, msg] };
    });
    // An open thread is being read right now, so it never becomes unread.
    if (msg.sender_id !== meId && friendId !== chatWith) {
      setUnread((prev) => ({ ...prev, [friendId]: (prev[friendId] || 0) + 1 }));
    } else if (msg.sender_id !== meId) {
      markThreadRead(meId, friendId).catch(() => undefined);
    }
  }, [meId, chatWith]);

  const totalUnread = Object.values(unread).reduce((sum, n) => sum + n, 0);

  return {
    threads, unread, totalUnread, chatWith,
    openChat, closeChat, reloadThread, send, wave, waveAll, whatsUp, pushIncoming, refreshUnread,
  };
}
