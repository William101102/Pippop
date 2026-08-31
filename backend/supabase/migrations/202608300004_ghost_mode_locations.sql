-- Ghost Mode: server-side location masking for friends.
-- Apply on a development Supabase project first.

create or replace function public.default_privacy_mode(p_owner uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select lp.mode from public.location_privacy lp where lp.owner_id = p_owner and lp.viewer_id is null),
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
    (select lp.mode from public.location_privacy lp where lp.owner_id = p_owner and lp.viewer_id = p_viewer),
    public.default_privacy_mode(p_owner)
  );
$$;

create or replace function public.blur_coord(base double precision, seed uuid, axis int)
returns double precision
language sql
immutable
as $$
  select base + (
    ((get_byte(decode(md5(seed::text || axis::text), 'hex'), 0) % 2) * 2 - 1)
    * (0.002 + (get_byte(decode(md5(seed::text || axis::text || 'm'), 'hex'), 1) % 101) * 0.0001)
  );
$$;

-- Column set has grown since this view was first created here (privacy_mode
-- was added later), and CREATE OR REPLACE VIEW cannot change a view's
-- existing columns — so drop it first rather than replace it in place.
drop view if exists public.friend_locations;
create view public.friend_locations
with (security_invoker = false)
as
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
      l.lat)
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred' then public.blur_coord(l.lat, l.user_id, 1)
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
      l.lng)
    when public.privacy_mode_for(l.user_id, auth.uid()) = 'blurred' then public.blur_coord(l.lng, l.user_id, 2)
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
   or (
     exists (
       select 1 from public.friendships f
       where f.status = 'accepted'
         and ((f.requester_id = auth.uid() and f.addressee_id = l.user_id)
           or (f.addressee_id = auth.uid() and f.requester_id = l.user_id))
     )
     and not exists (
       select 1 from public.blocks b
       where (b.blocker_id = l.user_id and b.blocked_id = auth.uid())
          or (b.blocker_id = auth.uid() and b.blocked_id = l.user_id)
     )
   );

grant select on public.friend_locations to authenticated;

-- Friends should read masked coordinates from the view, not raw locations.
drop policy if exists "view friends location" on public.locations;
create policy "view friends location"
  on public.locations for select
  using (auth.uid() = user_id);

alter table public.location_privacy enable row level security;
drop policy if exists "manage own privacy" on public.location_privacy;
create policy "manage own privacy"
  on public.location_privacy for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

do $$ begin
  alter publication supabase_realtime add table public.location_privacy;
exception when duplicate_object then null; end $$;
