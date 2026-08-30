import { useCallback, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { getSession, onAuthStateChange, signInWithPassword, signOut, signUp } from '../services/auth';
import { completeProfile, fetchProfile } from '../services/profiles';
import type { Profile } from '../types';

export function useAuth() {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [needsProfile, setNeedsProfile] = useState(false);

  const refreshProfile = useCallback(async (userId: string) => {
    const prof = await fetchProfile(userId);
    setProfile(prof);
    setNeedsProfile(!prof);
    return prof;
  }, []);

  useEffect(() => {
    let mounted = true;
    getSession().then(async (s) => {
      if (!mounted) return;
      setSession(s);
      if (s?.user) await refreshProfile(s.user.id);
      setReady(true);
    });
    const { data } = onAuthStateChange(async (s) => {
      setSession(s);
      if (s?.user) await refreshProfile(s.user.id);
      else {
        setProfile(null);
        setNeedsProfile(false);
      }
    });
    return () => {
      mounted = false;
      data.subscription.unsubscribe();
    };
  }, [refreshProfile]);

  const login = useCallback(async (email: string, password: string) => {
    const result = await signInWithPassword(email, password);
    if (result.error) return result;
    if (result.session?.user) await refreshProfile(result.session.user.id);
    return result;
  }, [refreshProfile]);

  const register = useCallback(async (input: { email: string; password: string; username: string; displayName: string }) => {
    const result = await signUp(input);
    if (result.error) return result;
    if (result.session?.user) await refreshProfile(result.session.user.id);
    return result;
  }, [refreshProfile]);

  const finishProfile = useCallback(async (userId: string, username: string, displayName: string) => {
    const result = await completeProfile(userId, username, displayName);
    if (result.error) return result;
    if (result.profile) setProfile(result.profile);
    setNeedsProfile(false);
    return result;
  }, []);

  const logout = useCallback(async () => {
    await signOut();
    setSession(null);
    setProfile(null);
    setNeedsProfile(false);
  }, []);

  return {
    ready,
    session,
    profile,
    needsProfile,
    signedIn: Boolean(session && profile),
    login,
    register,
    finishProfile,
    logout,
    setProfile,
  };
}
