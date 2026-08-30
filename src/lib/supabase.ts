import { createClient } from '@supabase/supabase-js';

// Public anon key — safe in frontend; override via .env.local or GitHub Actions vars.
const DEFAULT_URL = 'https://nzqgkbibuqnfbxfarswu.supabase.co';
const DEFAULT_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56cWdrYmlidXFuZmJ4ZmFyc3d1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMzg0NzgsImV4cCI6MjEwMzYxNDQ3OH0.olf2ccc_Y7yQj96Ls3BJja-jyJsr3YzUL2UXGFriApU';

const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined) || DEFAULT_URL;
const key = (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) || DEFAULT_ANON_KEY;

export const isConfigured = Boolean(url && key && !url.includes('your-project'));
export const supabase = createClient(url, key, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
