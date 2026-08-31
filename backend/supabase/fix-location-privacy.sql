-- ============================================================================
-- Fix: ghost mode save fails with "Failed to save privacy setting".
--
-- Cause: location_privacy used primary key (owner_id, viewer_id), but account-
-- wide defaults store viewer_id = null. PostgreSQL primary keys cannot contain
-- null, so inserts for blurred/frozen/precise defaults were rejected.
--
-- Safe to run more than once. Run it in the Supabase SQL Editor.
-- ============================================================================

alter table public.location_privacy drop constraint if exists location_privacy_pkey;
alter table public.location_privacy add column if not exists id bigint generated always as identity;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.location_privacy'::regclass
      and contype = 'p'
  ) then
    alter table public.location_privacy add constraint location_privacy_pkey primary key (id);
  end if;
exception when duplicate_object then null;
end $$;

create unique index if not exists location_privacy_account_default
  on public.location_privacy (owner_id) where viewer_id is null;
create unique index if not exists location_privacy_friend_override
  on public.location_privacy (owner_id, viewer_id) where viewer_id is not null;
