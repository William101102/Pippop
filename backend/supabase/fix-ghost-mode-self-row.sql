-- ============================================================================
-- Fix: ghost mode save fails on databases that never ran fix-location-privacy.sql
--
-- The app now stores account-wide defaults as owner_id = viewer_id (self row),
-- which works with the original composite primary key. This patch updates the
-- server helpers so friends still see blurred/frozen coordinates correctly.
--
-- Safe to run more than once. Run it in the Supabase SQL Editor.
-- ============================================================================

create or replace function public.default_privacy_mode(p_owner uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select lp.mode
        from public.location_privacy lp
       where lp.owner_id = p_owner
         and (lp.viewer_id is null or lp.viewer_id = p_owner)
       order by case when lp.viewer_id is null then 0 else 1 end
       limit 1
    ),
    'precise'
  );
$$;

create or replace function public.privacy_mode_for(p_owner uuid, p_viewer uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select lp.mode
        from public.location_privacy lp
       where lp.owner_id = p_owner
         and lp.viewer_id = p_viewer
         and lp.viewer_id <> p_owner
    ),
    public.default_privacy_mode(p_owner)
  );
$$;

create or replace view public.friend_locations with (security_invoker = false) as
select
  l.user_id,
  case
    when auth.uid() = l.user_id then l.lat
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'frozen' then coalesce(
      (
        select lp.frozen_lat
          from public.location_privacy lp
         where lp.owner_id = l.user_id
           and (lp.viewer_id is null or lp.viewer_id = l.user_id)
         order by case when lp.viewer_id is null then 0 else 1 end
         limit 1
      ),
      l.lat
    )
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred'
      then public.blur_coord(l.lat, l.user_id, 1)
    else l.lat
  end as lat,
  case
    when auth.uid() = l.user_id then l.lng
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'frozen' then coalesce(
      (
        select lp.frozen_lng
          from public.location_privacy lp
         where lp.owner_id = l.user_id
           and (lp.viewer_id is null or lp.viewer_id = l.user_id)
         order by case when lp.viewer_id is null then 0 else 1 end
         limit 1
      ),
      l.lng
    )
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred'
      then public.blur_coord(l.lng, l.user_id, 2)
    else l.lng
  end as lng,
  l.accuracy,
  l.speed,
  l.updated_at,
  case
    when auth.uid() = l.user_id then 'precise'
    else public.privacy_mode_for(l.user_id, auth.uid())
  end as privacy_mode
from public.locations l
where auth.uid() = l.user_id
   or public.shares_location_with(l.user_id, auth.uid());

grant select on public.friend_locations to authenticated;
