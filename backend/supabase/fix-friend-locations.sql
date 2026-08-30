-- ============================================================================
-- Fix: friends' locations were never visible ("暂无位置" for everyone).
--
-- Two separate causes, both server side:
--
-- 1. public.friend_locations was created with security_invoker = true, so
--    reading it applied the CALLER's RLS to public.locations. That table's
--    select policy only allowed `auth.uid() = user_id`, so every friend row was
--    filtered out before the view's friendship check could return it. The view
--    could only ever return your own location.
--
-- 2. Realtime evaluates RLS per subscriber and cannot subscribe to a view, so
--    the same owner-only policy meant friends' live location updates were never
--    delivered either.
--
-- Safe to run more than once. Run it in the Supabase SQL Editor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Shared visibility rule: accepted friendship either direction, neither side
-- has blocked the other. Security definer so calling it from inside an RLS
-- policy does not recurse into friendships'/blocks' own policies.
-- ----------------------------------------------------------------------------
create or replace function public.shares_location_with(p_owner uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_viewer is not null and exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = p_viewer and f.addressee_id = p_owner)
        or (f.addressee_id = p_viewer and f.requester_id = p_owner))
  ) and not exists (
    select 1 from public.blocks b
    where (b.blocker_id = p_owner and b.blocked_id = p_viewer)
       or (b.blocker_id = p_viewer and b.blocked_id = p_owner)
  );
$$;

-- ----------------------------------------------------------------------------
-- Cause 1. The view's own where clause is the access gate, so it must not
-- inherit the caller's owner-only RLS on public.locations.
-- ----------------------------------------------------------------------------
create or replace view public.friend_locations with (security_invoker = false) as
select
  l.user_id,
  case
    when auth.uid() = l.user_id then l.lat
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'frozen' then coalesce(
      (select lp.frozen_lat from public.location_privacy lp
        where lp.owner_id = l.user_id and lp.viewer_id is null), l.lat)
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred'
      then public.blur_coord(l.lat, l.user_id, 1)
    else l.lat
  end as lat,
  case
    when auth.uid() = l.user_id then l.lng
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'frozen' then coalesce(
      (select lp.frozen_lng from public.location_privacy lp
        where lp.owner_id = l.user_id and lp.viewer_id is null), l.lng)
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred'
      then public.blur_coord(l.lng, l.user_id, 2)
    else l.lng
  end as lng,
  l.accuracy,
  l.speed,
  l.updated_at
from public.locations l
where auth.uid() = l.user_id
   or public.shares_location_with(l.user_id, auth.uid());

revoke all on public.friend_locations from anon;
grant select on public.friend_locations to authenticated;

-- ----------------------------------------------------------------------------
-- Cause 2. Let friends select the raw row only in 'precise' mode, which is
-- byte-for-byte what the masked view already returns for that mode, so this
-- leaks nothing new. 'blurred' and 'frozen' rows stay readable only via the
-- view. This is what lets Realtime push friends' movement.
-- ----------------------------------------------------------------------------
drop policy if exists "view friends location" on public.locations;
create policy "view friends location" on public.locations for select
  using (
    auth.uid() = user_id
    or (
      public.shares_location_with(user_id, auth.uid())
      and public.privacy_mode_for(user_id, auth.uid()) = 'precise'
    )
  );

-- Locations must be in the Realtime publication for updates to be pushed.
do $$ begin alter publication supabase_realtime add table public.locations;
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- Self-check. Every row should read 'ok'.
-- ----------------------------------------------------------------------------
select 'friend_locations view exists' as check,
       case when to_regclass('public.friend_locations') is not null
            then 'ok' else 'MISSING' end as result
union all
select 'view does NOT use security_invoker',
       case when coalesce((
         select not ('security_invoker=true' = any(c.reloptions))
         from pg_class c where c.oid = 'public.friend_locations'::regclass
       ), true) then 'ok' else 'STILL BROKEN' end
union all
select 'shares_location_with() exists',
       case when exists (
         select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'shares_location_with'
       ) then 'ok' else 'MISSING' end
union all
select 'locations policy allows friends',
       case when exists (
         select 1 from pg_policies
         where schemaname = 'public' and tablename = 'locations'
           and policyname = 'view friends location'
           and qual like '%shares_location_with%'
       ) then 'ok' else 'MISSING' end
union all
select 'locations in realtime publication',
       case when exists (
         select 1 from pg_publication_tables
         where pubname = 'supabase_realtime' and schemaname = 'public'
           and tablename = 'locations'
       ) then 'ok' else 'MISSING' end
union all
select 'stored location rows (need > 0 to see anyone)',
       coalesce((select count(*)::text from public.locations), '0');
