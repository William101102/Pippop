-- ============================================================================
-- Fix: Ghost Mode save still fails with "隐私设置保存失败" even after running
-- setup.sql once.
--
-- Cause: setup.sql replaced the old composite primary key on location_privacy
-- with two PARTIAL unique indexes —
--   location_privacy_account_default  (owner_id)              where viewer_id is null
--   location_privacy_friend_override  (owner_id, viewer_id)    where viewer_id is not null
-- but src/services/profiles.ts always upserts with
--   .upsert(row, { onConflict: 'owner_id,viewer_id' })
-- (both the account-default row, keyed by viewer_id = owner_id, and per-friend
-- overrides use a non-null viewer_id — the client never writes viewer_id =
-- null itself). PostgREST can only target a plain, non-partial unique
-- index/constraint from an on_conflict column list; it cannot infer a partial
-- index unless the request also carries that index's WHERE predicate, which
-- the Supabase JS client does not send. So every upsert failed with Postgres
-- error 42P10 ("there is no unique or exclusion constraint matching the ON
-- CONFLICT specification"), surfaced in the app as the privacy save failing.
--
-- Fix: add a plain unique index covering (owner_id, viewer_id) so the
-- upsert's on_conflict target actually resolves. It coexists fine with the
-- two partial indexes already created by setup.sql.
--
-- Safe to run more than once. Run it in the Supabase SQL Editor. Also folded
-- into setup.sql, so re-running setup.sql picks this up too.
-- ============================================================================

create unique index if not exists location_privacy_owner_viewer_key
  on public.location_privacy (owner_id, viewer_id);
