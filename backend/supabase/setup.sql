-- ============================================================================
-- Pinpop — complete database setup.
--
-- Run this whole file in the Supabase SQL Editor. It is idempotent: running it
-- again is safe and is the way to pick up later changes. It supersedes running
-- the individual files in migrations/ by hand, which drifted apart (two copies
-- of location_history with different columns, policies without DROP guards).
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- Core tables
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null default '',
  avatar_color text not null default '#ff6847',
  status_emoji text not null default '✨',
  status_text text not null default '刚刚加入 Pinpop',
  created_at timestamptz not null default now()
);

-- Column-level guards in case an older prototype table is already in place.
alter table public.profiles add column if not exists display_name text not null default '';
alter table public.profiles add column if not exists avatar_color text not null default '#ff6847';
alter table public.profiles add column if not exists status_emoji text not null default '✨';
alter table public.profiles add column if not exists status_text text not null default '刚刚加入 Pinpop';
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists bio text not null default '';
alter table public.profiles add column if not exists battery_level smallint;
alter table public.profiles add column if not exists is_charging boolean not null default false;
alter table public.profiles add column if not exists last_active_at timestamptz not null default now();

do $$ begin
  alter table public.profiles add constraint profiles_battery_range
    check (battery_level is null or battery_level between 0 and 100);
exception when duplicate_object then null; end $$;

create table if not exists public.locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);

alter table public.locations add column if not exists accuracy double precision;
alter table public.locations add column if not exists altitude double precision;
alter table public.locations add column if not exists speed double precision;
alter table public.locations add column if not exists heading double precision;

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);

alter table public.friendships add column if not exists created_at timestamptz not null default now();

-- Two people who added each other at the same time produced two rows for one
-- relationship, which blocks the unique index below. Collapse each pair to a
-- single row, keeping the most meaningful status: accepted > pending > declined.
with ranked as (
  select
    id,
    row_number() over (
      partition by least(requester_id, addressee_id), greatest(requester_id, addressee_id)
      order by
        case status when 'accepted' then 0 when 'pending' then 1 else 2 end,
        created_at,
        id
    ) as rn
  from public.friendships
)
delete from public.friendships f
using ranked r
where f.id = r.id and r.rn > 1;

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.messages add column if not exists kind text not null default 'text';
alter table public.messages add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.messages add column if not exists read_at timestamptz;

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'emoji', 'wave', 'image', 'location', 'whats_up'));

alter table public.messages drop constraint if exists messages_body_length;
alter table public.messages add constraint messages_body_length
  check (char_length(trim(body)) between 1 and 2000);

-- ----------------------------------------------------------------------------
-- Privacy, history and places
-- ----------------------------------------------------------------------------
create table if not exists public.location_privacy (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid references public.profiles(id) on delete cascade,
  mode text not null default 'precise' check (mode in ('precise', 'blurred', 'frozen')),
  frozen_lat double precision,
  frozen_lng double precision,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (owner_id, viewer_id)
);

create table if not exists public.location_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- The prototype shipped this table without the grid columns the client writes,
-- so add them here rather than relying on the CREATE above.
alter table public.location_history add column if not exists accuracy double precision;
alter table public.location_history add column if not exists cell_lat bigint;
alter table public.location_history add column if not exists cell_lng bigint;
alter table public.location_history add column if not exists created_at timestamptz not null default now();

create table if not exists public.significant_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('overnight', 'home', 'work')),
  lat double precision not null,
  lng double precision not null,
  label text not null default '',
  score numeric not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  cell_lat bigint not null,
  cell_lng bigint not null,
  unique (user_id, kind, cell_lat, cell_lng)
);

create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'other',
  address text,
  lat double precision not null,
  lng double precision not null,
  source text not null default 'user',
  created_at timestamptz not null default now()
);
alter table public.places add column if not exists created_by uuid references public.profiles(id) on delete set null;

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  arrived_at timestamptz not null default now(),
  departed_at timestamptz,
  visibility text not null default 'private' check (visibility in ('private', 'friends', 'public')),
  note text,
  check (departed_at is null or departed_at >= arrived_at)
);

create table if not exists public.highlights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  place_id uuid references public.places(id) on delete set null,
  body text not null default '',
  media_url text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.whats_up_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'answered', 'declined', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 hours'),
  check (sender_id <> recipient_id)
);

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
create unique index if not exists friendships_pair_unique
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists messages_pair_time_idx
  on public.messages (sender_id, recipient_id, created_at desc);
create index if not exists messages_unread_idx
  on public.messages (recipient_id, read_at) where read_at is null;
create index if not exists location_history_user_time_idx
  on public.location_history (user_id, recorded_at desc);
create index if not exists places_lat_lng_idx on public.places (lat, lng);
create index if not exists places_created_by_idx on public.places (created_by);
create index if not exists visits_user_time_idx on public.visits (user_id, arrived_at desc);
create index if not exists visits_place_idx on public.visits (place_id, arrived_at desc);

-- ----------------------------------------------------------------------------
-- Privacy helpers. Defined before the policies below because those reference
-- them, and all are security definer so reading friendships/blocks/privacy from
-- inside a policy does not recurse into those tables' own RLS.
-- ----------------------------------------------------------------------------
create or replace function public.default_privacy_mode(p_owner uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lp.mode from public.location_privacy lp
      where lp.owner_id = p_owner and lp.viewer_id is null),
    'precise'
  );
$$;

create or replace function public.privacy_mode_for(p_owner uuid, p_viewer uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lp.mode from public.location_privacy lp
      where lp.owner_id = p_owner and lp.viewer_id = p_viewer),
    public.default_privacy_mode(p_owner)
  );
$$;

create or replace function public.blur_coord(base double precision, seed uuid, axis int)
returns double precision language sql immutable as $$
  select base + (((get_byte(decode(md5(seed::text || axis::text), 'hex'), 0) % 200) - 100) * 0.009);
$$;

-- Accepted friendship in either direction, and neither side has blocked the
-- other. Shared by friend_locations and the locations select policy so both
-- gate visibility identically.
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
-- Row level security
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.locations enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;
alter table public.location_privacy enable row level security;
alter table public.location_history enable row level security;
alter table public.significant_places enable row level security;
alter table public.places enable row level security;
alter table public.visits enable row level security;
alter table public.highlights enable row level security;
alter table public.blocks enable row level security;
alter table public.whats_up_requests enable row level security;

-- Profiles: every signed-in user can search others; you may only edit your own.
drop policy if exists "authenticated read profiles" on public.profiles;
create policy "authenticated read profiles" on public.profiles for select
  to authenticated using (true);

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile" on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);

-- Locations. Realtime evaluates this policy per subscriber and cannot subscribe
-- to a view, so friends need select on the raw row or their live updates never
-- arrive. Exposing it only for 'precise' mode leaks nothing the masked
-- friend_locations view would not already return verbatim, while 'blurred' and
-- 'frozen' rows stay readable only through that view.
drop policy if exists "view friends location" on public.locations;
create policy "view friends location" on public.locations for select
  using (
    auth.uid() = user_id
    or (
      public.shares_location_with(user_id, auth.uid())
      and public.privacy_mode_for(user_id, auth.uid()) = 'precise'
    )
  );

drop policy if exists "insert own location" on public.locations;
create policy "insert own location" on public.locations for insert
  with check (auth.uid() = user_id);

drop policy if exists "update own location" on public.locations;
create policy "update own location" on public.locations for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Friendships.
drop policy if exists "read own friendships" on public.friendships;
create policy "read own friendships" on public.friendships for select
  using (auth.uid() in (requester_id, addressee_id));

drop policy if exists "create friend request" on public.friendships;
create policy "create friend request" on public.friendships for insert
  with check (auth.uid() = requester_id and requester_id <> addressee_id and status = 'pending');

drop policy if exists "respond to friend request" on public.friendships;
create policy "respond to friend request" on public.friendships for update
  using (auth.uid() = addressee_id and status = 'pending')
  with check (auth.uid() = addressee_id and status in ('accepted', 'declined'));

drop policy if exists "remove own friendship" on public.friendships;
create policy "remove own friendship" on public.friendships for delete
  using (auth.uid() in (requester_id, addressee_id));

-- Messages.
drop policy if exists "read own conversations" on public.messages;
create policy "read own conversations" on public.messages for select
  using (auth.uid() in (sender_id, recipient_id));

drop policy if exists "send message to friend" on public.messages;
create policy "send message to friend" on public.messages for insert
  with check (
    auth.uid() = sender_id
    and sender_id <> recipient_id
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = recipient_id)
          or (f.addressee_id = auth.uid() and f.requester_id = recipient_id))
    )
  );

drop policy if exists "mark received message read" on public.messages;
create policy "mark received message read" on public.messages for update
  using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

-- Private per-user data.
drop policy if exists "manage own privacy" on public.location_privacy;
create policy "manage own privacy" on public.location_privacy for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "manage own location history" on public.location_history;
create policy "manage own location history" on public.location_history for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "manage own significant places" on public.significant_places;
create policy "manage own significant places" on public.significant_places for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Places: readable by any signed-in user, writable only as your own check-in.
drop policy if exists "authenticated read places" on public.places;
create policy "authenticated read places" on public.places for select
  to authenticated using (true);

drop policy if exists "create user place" on public.places;
create policy "create user place" on public.places for insert
  with check (auth.uid() = created_by and source = 'user');

drop policy if exists "update own place" on public.places;
create policy "update own place" on public.places for update
  using (auth.uid() = created_by) with check (auth.uid() = created_by);

drop policy if exists "delete own place" on public.places;
create policy "delete own place" on public.places for delete
  using (auth.uid() = created_by);

-- Visits.
drop policy if exists "read visible visits" on public.visits;
create policy "read visible visits" on public.visits for select using (
  auth.uid() = user_id or (visibility = 'friends' and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester_id = auth.uid() and f.addressee_id = visits.user_id) or
       (f.addressee_id = auth.uid() and f.requester_id = visits.user_id)))));

drop policy if exists "manage own visits" on public.visits;
create policy "manage own visits" on public.visits for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Highlights, blocks, What's Up.
drop policy if exists "read friend highlights" on public.highlights;
create policy "read friend highlights" on public.highlights for select using (
  auth.uid() = user_id or (expires_at > now() and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester_id = auth.uid() and f.addressee_id = highlights.user_id) or
       (f.addressee_id = auth.uid() and f.requester_id = highlights.user_id)))));

drop policy if exists "manage own highlights" on public.highlights;
create policy "manage own highlights" on public.highlights for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "manage own blocks" on public.blocks;
create policy "manage own blocks" on public.blocks for all
  using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);

drop policy if exists "see own whats up" on public.whats_up_requests;
create policy "see own whats up" on public.whats_up_requests for select
  using (auth.uid() in (sender_id, recipient_id));

drop policy if exists "send whats up to friend" on public.whats_up_requests;
create policy "send whats up to friend" on public.whats_up_requests for insert with check (
  auth.uid() = sender_id and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester_id = auth.uid() and f.addressee_id = recipient_id) or
       (f.addressee_id = auth.uid() and f.requester_id = recipient_id))));

drop policy if exists "answer whats up" on public.whats_up_requests;
create policy "answer whats up" on public.whats_up_requests for update
  using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

-- ----------------------------------------------------------------------------
-- Ghost Mode: friends read masked coordinates from this view, never raw rows.
-- ----------------------------------------------------------------------------
-- security_invoker must stay off: this view is the only sanctioned way to read
-- someone else's coordinates, so it has to out-live the owner-only select
-- policy on public.locations. Its own where clause is the access gate.
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

grant select on public.friend_locations to authenticated;

-- ----------------------------------------------------------------------------
-- Avatar storage
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 12582912, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "users upload their own avatar" on storage.objects;
create policy "users upload their own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users update their own avatar" on storage.objects;
create policy "users update their own avatar" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users delete their own avatar" on storage.objects;
create policy "users delete their own avatar" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ----------------------------------------------------------------------------
-- Every Auth user gets a profile, including ones created before this ran.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  requested_username text;
  safe_username text;
  chosen_name text;
begin
  requested_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'username', ''), '[^a-z0-9_]', '', 'g'));
  if char_length(requested_username) < 3 then
    requested_username := 'user_' || left(replace(new.id::text, '-', ''), 8);
  end if;

  safe_username := requested_username;
  if exists (select 1 from public.profiles where username = safe_username) then
    safe_username := left(requested_username, 20) || '_' || left(replace(new.id::text, '-', ''), 5);
  end if;

  chosen_name := nullif(trim(new.raw_user_meta_data->>'display_name'), '');
  insert into public.profiles (id, username, display_name, avatar_color, status_emoji, status_text)
  values (
    new.id,
    safe_username,
    coalesce(chosen_name, split_part(coalesce(new.email, safe_username), '@', 1)),
    '#ff6847', '✨', '刚刚加入 Pinpop'
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into public.profiles (id, username, display_name, avatar_color, status_emoji, status_text)
select
  u.id,
  'user_' || left(replace(u.id::text, '-', ''), 8),
  split_part(coalesce(u.email, 'New friend'), '@', 1),
  '#ff6847', '✨', '刚刚加入 Pinpop'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- Realtime: the client subscribes to these three tables.
-- ----------------------------------------------------------------------------
do $$ begin alter publication supabase_realtime add table public.locations;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.friendships;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.location_privacy;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.highlights;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.whats_up_requests;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.visits;
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- Result: one row per thing the app needs. Everything should read "ok".
-- ----------------------------------------------------------------------------
select 'profiles table' as item,
       case when to_regclass('public.profiles') is not null then 'ok' else 'MISSING' end as status
union all select 'messages.read_at column',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'messages' and column_name = 'read_at')
       then 'ok' else 'MISSING' end
union all select 'location_history.cell_lat column',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'location_history' and column_name = 'cell_lat')
       then 'ok' else 'MISSING' end
union all select 'places.created_by column',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'places' and column_name = 'created_by')
       then 'ok' else 'MISSING' end
union all select 'significant_places table',
       case when to_regclass('public.significant_places') is not null then 'ok' else 'MISSING' end
union all select 'friend_locations view',
       case when to_regclass('public.friend_locations') is not null then 'ok' else 'MISSING' end
union all select 'avatars storage bucket',
       case when exists (select 1 from storage.buckets where id = 'avatars') then 'ok' else 'MISSING' end
union all select 'places insert policy',
       case when exists (select 1 from pg_policies
         where schemaname = 'public' and tablename = 'places' and policyname = 'create user place')
       then 'ok' else 'MISSING' end
union all select 'realtime on messages',
       case when exists (select 1 from pg_publication_tables
         where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages')
       then 'ok' else 'MISSING' end
union all select 'friendships deduplicated',
       case when exists (
         select 1 from public.friendships
         group by least(requester_id, addressee_id), greatest(requester_id, addressee_id)
         having count(*) > 1)
       then 'DUPLICATES REMAIN' else 'ok' end
order by item;
