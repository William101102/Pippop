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
  status_text text not null default 'Just joined Pinpop',
  created_at timestamptz not null default now()
);

-- Column-level guards in case an older prototype table is already in place.
alter table public.profiles add column if not exists display_name text not null default '';
alter table public.profiles add column if not exists avatar_color text not null default '#ff6847';
alter table public.profiles add column if not exists status_emoji text not null default '✨';
alter table public.profiles add column if not exists status_text text not null default 'Just joined Pinpop';
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
  id bigint generated always as identity,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid references public.profiles(id) on delete cascade,
  mode text not null default 'precise' check (mode in ('precise', 'blurred', 'frozen')),
  frozen_lat double precision,
  frozen_lng double precision,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Account-wide defaults use viewer_id = null, which cannot sit in a composite PK.
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
-- The client always upserts with .upsert(row, { onConflict: 'owner_id,viewer_id' })
-- — both the account-default row (viewer_id = owner_id) and per-friend
-- overrides use a non-null viewer_id; it never writes viewer_id = null itself.
-- PostgREST's on_conflict target can only resolve to a plain, non-partial
-- unique index/constraint on exactly those columns, and neither partial index
-- above qualifies, so every save failed with 42P10 "no unique or exclusion
-- constraint matching the ON CONFLICT specification" — the real cause behind
-- "Failed to save privacy setting". This plain index is what upsert actually needs.
create unique index if not exists location_privacy_owner_viewer_key
  on public.location_privacy (owner_id, viewer_id);

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
-- Opt-in location on a highlight — renders as a story pin on the map, à la
-- Snap Map, until it expires. Null unless the author chose to attach it.
alter table public.highlights add column if not exists lat double precision;
alter table public.highlights add column if not exists lng double precision;

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

-- "Zenlands": friend-visible, hand-named zones (unlike the private,
-- auto-detected significant_places above). Arrive/leave detection always
-- runs on the owner's own device; friends just need to read the label.
create table if not exists public.zones (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 24),
  emoji text not null default '📍',
  lat double precision not null,
  lng double precision not null,
  radius_m int not null default 120 check (radius_m between 30 and 500),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- Social layer
-- ----------------------------------------------------------------------------

-- An emoji dropped onto a friend's pin. Short lived so the map stays readable.
create table if not exists public.map_reactions (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 hour')
);

-- Pinned favourites, per direction: marking someone does not mark you back.
create table if not exists public.best_friends (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);

-- Streaks live on the friendship because that table already holds exactly one
-- row per pair, so a streak cannot disagree with itself between directions.
alter table public.friendships add column if not exists streak_days integer not null default 0;
alter table public.friendships add column if not exists longest_streak integer not null default 0;
alter table public.friendships add column if not exists last_interaction_on date;

-- "Alex arrived at Office". Written by the mover's own device, since only it knows which
-- of the user's private significant places a fix corresponds to.
create table if not exists public.place_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('arrive', 'leave')),
  label text not null default '',
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now()
);

-- Group chat. A message either belongs to a 1:1 pair (recipient_id set,
-- group_id null) or a group (group_id set, recipient_id null) — see the
-- messages_recipient_or_group check added below.
create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.messages add column if not exists group_id uuid references public.chat_groups(id) on delete cascade;
-- A group message has no single recipient.
alter table public.messages alter column recipient_id drop not null;
alter table public.messages drop constraint if exists messages_recipient_or_group;
alter table public.messages add constraint messages_recipient_or_group check (
  (group_id is null and recipient_id is not null) or (group_id is not null and recipient_id is null)
);

-- Invite-link tokens. Possessing one — because its owner shared it directly
-- with you — is treated as that owner's consent to friend whoever redeems
-- it, the same trust model Discord/WhatsApp invite links use. Redemption
-- only ever happens through the redeem_invite() security-definer function
-- below, never by inserting into this table directly.
create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  use_count integer not null default 0
);
create index if not exists invites_owner_idx on public.invites (owner_id);

-- One row per device. Tokens rotate, so the token itself is the identity.
create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'ios' check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now()
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
-- Heatmap and frequent places both group history by grid cell.
create index if not exists location_history_cell_idx
  on public.location_history (user_id, cell_lat, cell_lng);
create index if not exists map_reactions_target_idx
  on public.map_reactions (target_id, created_at desc);
create index if not exists place_events_user_time_idx
  on public.place_events (user_id, created_at desc);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
create index if not exists highlights_user_time_idx
  on public.highlights (user_id, created_at desc);
create index if not exists highlights_expires_idx
  on public.highlights (expires_at);
create index if not exists zones_owner_idx on public.zones (owner_id);
create index if not exists chat_group_members_user_idx
  on public.chat_group_members (user_id);
create index if not exists messages_group_time_idx
  on public.messages (group_id, created_at) where group_id is not null;

-- ----------------------------------------------------------------------------
-- Privacy helpers. Defined before the policies below because those reference
-- them, and all are security definer so reading friendships/blocks/privacy from
-- inside a policy does not recurse into those tables' own RLS.
-- ----------------------------------------------------------------------------
create or replace function public.default_privacy_mode(p_owner uuid)
returns text language sql stable security definer set search_path = public as $$
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
returns text language sql stable security definer set search_path = public as $$
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

-- Stable offset of about 0.2–1.2 km per axis, so "blurred" still reads as
-- the same neighbourhood instead of jumping a city away.
create or replace function public.blur_coord(base double precision, seed uuid, axis int)
returns double precision language sql immutable as $$
  select base + (
    ((get_byte(decode(md5(seed::text || axis::text), 'hex'), 0) % 2) * 2 - 1)
    * (0.002 + (get_byte(decode(md5(seed::text || axis::text || 'm'), 'hex'), 1) % 101) * 0.0001)
  );
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

-- security definer so this can be called from inside chat_group_members' own
-- RLS (and messages') without recursing into chat_group_members' policies.
create or replace function public.is_group_member(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_group_members m
    where m.group_id = p_group and m.user_id = p_user
  );
$$;

-- "People you may know": friends of your friends, ranked by how many of
-- your friends they share, with one of those mutual friends' names attached
-- so the client can show "Friends with Maya" instead of a bare profile.
-- Security definer because a normal client query cannot see a stranger's
-- friendships rows at all (RLS only exposes rows you're party to) — this
-- computes the two-hop graph server-side and returns only the minimal
-- profile fields needed for a suggestion card, never the underlying edges.
create or replace function public.suggested_friends(p_limit int default 12)
returns table(
  id uuid,
  display_name text,
  username text,
  avatar_url text,
  avatar_color text,
  status_emoji text,
  mutual_count int,
  mutual_name text
)
language sql stable security definer set search_path = public as $$
  with my_friends as (
    select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as friend_id
    from public.friendships f
    where f.status = 'accepted' and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
  ),
  -- Every (candidate, introduced-by) pair reachable in exactly two hops.
  candidates as (
    select
      case when f2.requester_id = mf.friend_id then f2.addressee_id else f2.requester_id end as candidate_id,
      mf.friend_id as via_friend_id
    from my_friends mf
    join public.friendships f2
      on f2.status = 'accepted'
      and (f2.requester_id = mf.friend_id or f2.addressee_id = mf.friend_id)
  ),
  filtered as (
    select c.candidate_id, c.via_friend_id
    from candidates c
    where c.candidate_id <> auth.uid()
      and c.candidate_id not in (select friend_id from my_friends)
      -- Skip anyone with a pending/declined request between us either way,
      -- and anyone blocked in either direction.
      and not exists (
        select 1 from public.friendships f3
        where (f3.requester_id = auth.uid() and f3.addressee_id = c.candidate_id)
           or (f3.requester_id = c.candidate_id and f3.addressee_id = auth.uid())
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = c.candidate_id)
           or (b.blocker_id = c.candidate_id and b.blocked_id = auth.uid())
      )
  ),
  agg as (
    select candidate_id, count(distinct via_friend_id) as mutual_count
    from filtered
    group by candidate_id
  ),
  -- One representative mutual friend per candidate, for the "Friends with
  -- ___" label — which one is arbitrary but stable (lowest id) so the label
  -- does not flicker between refreshes.
  one_mutual as (
    select distinct on (candidate_id) candidate_id, via_friend_id
    from filtered
    order by candidate_id, via_friend_id
  )
  select
    p.id, p.display_name, p.username, p.avatar_url, p.avatar_color, p.status_emoji,
    a.mutual_count::int, mp.display_name as mutual_name
  from agg a
  join one_mutual om on om.candidate_id = a.candidate_id
  join public.profiles p on p.id = a.candidate_id
  join public.profiles mp on mp.id = om.via_friend_id
  order by a.mutual_count desc, p.display_name asc
  limit p_limit;
$$;
grant execute on function public.suggested_friends(int) to authenticated;

-- Redeems an invite-link token into an immediately-accepted friendship.
-- Security definer so it can write an 'accepted' row directly, bypassing the
-- normal "create friend request" policy (which only ever allows 'pending')
-- — the token itself, minted by create_invite_token-equivalent client insert
-- and shared privately by its owner, stands in for that owner's consent.
create or replace function public.redeem_invite(p_token uuid)
returns table(owner_id uuid) language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
begin
  select i.owner_id into v_owner
    from public.invites i
   where i.id = p_token
     and (i.expires_at is null or i.expires_at > now());

  if v_owner is null then
    raise exception 'invite not found or expired';
  end if;
  if v_owner = auth.uid() then
    raise exception 'cannot redeem your own invite';
  end if;

  if exists (
    select 1 from public.friendships f
    where (f.requester_id = v_owner and f.addressee_id = auth.uid())
       or (f.requester_id = auth.uid() and f.addressee_id = v_owner)
  ) then
    update public.friendships f set status = 'accepted'
     where (f.requester_id = v_owner and f.addressee_id = auth.uid())
        or (f.requester_id = auth.uid() and f.addressee_id = v_owner);
  else
    insert into public.friendships (requester_id, addressee_id, status)
    values (auth.uid(), v_owner, 'accepted');
  end if;

  update public.invites set use_count = use_count + 1 where id = p_token;

  return query select v_owner;
end;
$$;
grant execute on function public.redeem_invite(uuid) to authenticated;

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
alter table public.map_reactions enable row level security;
alter table public.best_friends enable row level security;
alter table public.place_events enable row level security;
alter table public.push_tokens enable row level security;
alter table public.zones enable row level security;
alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.invites enable row level security;

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

-- Messages. A row is either a 1:1 message (recipient_id set) or a group
-- message (group_id set) — the check constraint on the table guarantees
-- exactly one, so each policy below just adds the alternate branch.
drop policy if exists "read own conversations" on public.messages;
create policy "read own conversations" on public.messages for select
  using (
    auth.uid() in (sender_id, recipient_id)
    or (group_id is not null and public.is_group_member(group_id, auth.uid()))
  );

drop policy if exists "send message to friend" on public.messages;
create policy "send message to friend" on public.messages for insert
  with check (
    auth.uid() = sender_id
    and (
      (
        group_id is null and sender_id <> recipient_id
        and exists (
          select 1 from public.friendships f
          where f.status = 'accepted'
            and ((f.requester_id = auth.uid() and f.addressee_id = recipient_id)
              or (f.addressee_id = auth.uid() and f.requester_id = recipient_id))
        )
      )
      or (
        group_id is not null and recipient_id is null
        and public.is_group_member(group_id, auth.uid())
      )
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

-- Zenlands: you manage your own; friends can only read the label/location so
-- an arrive/leave notice makes sense to them.
drop policy if exists "manage own zones" on public.zones;
create policy "manage own zones" on public.zones for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

drop policy if exists "friends read zones" on public.zones;
create policy "friends read zones" on public.zones for select
  using (auth.uid() = owner_id or public.shares_location_with(owner_id, auth.uid()));

-- Invites: you can create/see/revoke your own links. Nobody else can select
-- this table directly — redemption goes through redeem_invite() only, so a
-- token's validity can't be probed by querying the table.
drop policy if exists "manage own invites" on public.invites;
create policy "manage own invites" on public.invites for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Group chat: only the creator can make a group or add its first members;
-- membership itself is otherwise read-only from the client for v1 (no
-- leave/add-later flow yet).
drop policy if exists "read my groups" on public.chat_groups;
create policy "read my groups" on public.chat_groups for select
  using (public.is_group_member(id, auth.uid()));

drop policy if exists "create own group" on public.chat_groups;
create policy "create own group" on public.chat_groups for insert
  with check (auth.uid() = owner_id);

drop policy if exists "delete own group" on public.chat_groups;
create policy "delete own group" on public.chat_groups for delete
  using (auth.uid() = owner_id);

drop policy if exists "read fellow group members" on public.chat_group_members;
create policy "read fellow group members" on public.chat_group_members for select
  using (public.is_group_member(group_id, auth.uid()));

-- Only the group's owner can seat members (including themself) — a plain
-- "or user_id = auth.uid()" branch here would let a stranger self-join any
-- group whose id they can guess, so it's deliberately not offered.
drop policy if exists "owner adds group members" on public.chat_group_members;
create policy "owner adds group members" on public.chat_group_members for insert
  with check (
    exists (select 1 from public.chat_groups g where g.id = group_id and g.owner_id = auth.uid())
  );

drop policy if exists "leave own group membership" on public.chat_group_members;
create policy "leave own group membership" on public.chat_group_members for delete
  using (auth.uid() = user_id);

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

-- Map reactions: sender and target can see them, friends only. Reuses the same
-- visibility rule as locations so a blocked user cannot poke you on the map.
drop policy if exists "read own reactions" on public.map_reactions;
create policy "read own reactions" on public.map_reactions for select using (
  auth.uid() = sender_id
  or (auth.uid() = target_id and public.shares_location_with(sender_id, auth.uid()))
);

drop policy if exists "send reaction to friend" on public.map_reactions;
create policy "send reaction to friend" on public.map_reactions for insert with check (
  auth.uid() = sender_id and public.shares_location_with(target_id, auth.uid())
);

drop policy if exists "delete own reaction" on public.map_reactions;
create policy "delete own reaction" on public.map_reactions for delete
  using (auth.uid() = sender_id);

-- Best friends are private to whoever pinned them.
drop policy if exists "manage own best friends" on public.best_friends;
create policy "manage own best friends" on public.best_friends for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Place events: your own, plus friends' who still share location with you.
drop policy if exists "read friend place events" on public.place_events;
create policy "read friend place events" on public.place_events for select using (
  auth.uid() = user_id or public.shares_location_with(user_id, auth.uid())
);

drop policy if exists "write own place events" on public.place_events;
create policy "write own place events" on public.place_events for insert
  with check (auth.uid() = user_id);

-- Push tokens are never readable by other users; only the service role sends.
drop policy if exists "manage own push tokens" on public.push_tokens;
create policy "manage own push tokens" on public.push_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

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
      (
        select lp.frozen_lat
          from public.location_privacy lp
         where lp.owner_id = l.user_id
           and (lp.viewer_id is null or lp.viewer_id = l.user_id)
         order by case when lp.viewer_id is null then 0 else 1 end
         limit 1
      ),
      l.lat)
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
      l.lng)
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

-- Public bucket still needs a select policy or uploaded photos 403 in the app.
drop policy if exists "avatars are publicly readable" on storage.objects;
create policy "avatars are publicly readable" on storage.objects for select
  using (bucket_id = 'avatars');

-- ----------------------------------------------------------------------------
-- Footprints. Reads only the caller's own history; the grid columns the client
-- already writes make the aggregation cheap enough to run on demand.
-- ----------------------------------------------------------------------------
create or replace function public.my_heatmap(p_days integer default 30)
returns table (cell_lat bigint, cell_lng bigint, lat double precision, lng double precision, hits bigint)
language sql stable security definer set search_path = public as $$
  select h.cell_lat, h.cell_lng, avg(h.lat), avg(h.lng), count(*)
    from public.location_history h
   where h.user_id = auth.uid()
     and h.cell_lat is not null
     and h.recorded_at > now() - make_interval(days => greatest(p_days, 1))
   group by h.cell_lat, h.cell_lng
   order by count(*) desc
   limit 600;
$$;

/**
 * Frequent places with a dwell estimate. Consecutive fixes in the same cell are
 * treated as one stay, and gaps longer than an hour end it, so a phone that was
 * simply switched off overnight does not read as a 12 hour visit.
 */
create or replace function public.my_frequent_places(p_days integer default 30)
returns table (
  cell_lat bigint,
  cell_lng bigint,
  lat double precision,
  lng double precision,
  visits bigint,
  minutes numeric,
  last_seen timestamptz
) language sql stable security definer set search_path = public as $$
  with fixes as (
    select h.cell_lat, h.cell_lng, h.lat, h.lng, h.recorded_at,
           lag(h.cell_lat) over w as prev_lat_cell,
           lag(h.cell_lng) over w as prev_lng_cell,
           lag(h.recorded_at) over w as prev_at
      from public.location_history h
     where h.user_id = auth.uid()
       and h.cell_lat is not null
       and h.recorded_at > now() - make_interval(days => greatest(p_days, 1))
    window w as (order by h.recorded_at)
  ), marked as (
    select *,
           case
             when prev_lat_cell is distinct from cell_lat
               or prev_lng_cell is distinct from cell_lng
               or prev_at is null
               or recorded_at - prev_at > interval '1 hour'
             then 1 else 0
           end as starts_stay
      from fixes
  ), grouped as (
    select *, sum(starts_stay) over (order by recorded_at) as stay_id from marked
  ), stays as (
    select cell_lat, cell_lng, avg(lat) as lat, avg(lng) as lng,
           min(recorded_at) as began, max(recorded_at) as ended
      from grouped
     group by stay_id, cell_lat, cell_lng
  )
  select cell_lat, cell_lng, avg(lat), avg(lng), count(*),
         round(sum(extract(epoch from (ended - began)) / 60)::numeric, 1),
         max(ended)
    from stays
   group by cell_lat, cell_lng
   order by sum(extract(epoch from (ended - began))) desc, count(*) desc
   limit 40;
$$;

-- ----------------------------------------------------------------------------
-- Interaction streaks. Bumped from triggers on messages AND map_reactions
-- (throwing something at a friend keeps the streak alive too — Snapchat's
-- streaks count any snap, not just a typed one) so the count cannot drift
-- from actual activity, and kept symmetric by living on the pair.
--
-- Missing exactly one day is forgivable: the pair gets one "repair" shot —
-- three consecutive days back and the streak is restored as if it never
-- broke (streak_grace_value + 3), same generous-but-bounded spirit as most
-- big social apps' streak-restore mechanics. Missing more than one day, or
-- missing again mid-repair, is a clean reset — no repair chains.
-- ----------------------------------------------------------------------------
alter table public.friendships add column if not exists streak_grace_value integer;
alter table public.friendships add column if not exists streak_grace_days integer not null default 0;

create or replace function public.bump_friend_streak(p_a uuid, p_b uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'utc')::date;
  rec record;
  gap integer;
  new_streak integer;
  new_grace_value integer;
  new_grace_days integer;
begin
  for rec in
    select * from public.friendships f
     where f.status = 'accepted'
       and ((f.requester_id = p_a and f.addressee_id = p_b)
         or (f.addressee_id = p_a and f.requester_id = p_b))
     for update
  loop
    if rec.last_interaction_on = today then
      continue; -- already counted today
    end if;

    gap := case when rec.last_interaction_on is null then null else today - rec.last_interaction_on end;

    if gap = 1 then
      -- Back-to-back day: normal continuation, and — if a repair is already
      -- in progress — one more step toward completing it.
      new_streak := coalesce(rec.streak_days, 0) + 1;
      if rec.streak_grace_value is not null then
        new_grace_days := rec.streak_grace_days + 1;
        if new_grace_days >= 3 then
          new_streak := rec.streak_grace_value + new_grace_days;
          new_grace_value := null;
          new_grace_days := 0;
        else
          new_grace_value := rec.streak_grace_value;
        end if;
      else
        new_grace_value := null;
        new_grace_days := 0;
      end if;
    elsif gap = 2 then
      -- Exactly one day missed: start the one-time repair window.
      new_grace_value := coalesce(rec.streak_days, 0);
      new_grace_days := 1;
      new_streak := 1;
    else
      -- Missed more than one day (or first-ever interaction, or a repair
      -- that itself lapsed): clean reset, no repair eligibility.
      new_grace_value := null;
      new_grace_days := 0;
      new_streak := 1;
    end if;

    update public.friendships f
       set streak_days = new_streak,
           streak_grace_value = new_grace_value,
           streak_grace_days = new_grace_days,
           last_interaction_on = today,
           longest_streak = greatest(f.longest_streak, new_streak)
     where f.id = rec.id;
  end loop;
end;
$$;

create or replace function public.touch_friend_streak()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- new.recipient_id is null for a group message, so the update inside
  -- bump_friend_streak simply matches zero rows — a safe no-op.
  perform public.bump_friend_streak(new.sender_id, new.recipient_id);
  return new;
end;
$$;

drop trigger if exists messages_touch_streak on public.messages;
create trigger messages_touch_streak
  after insert on public.messages
  for each row execute function public.touch_friend_streak();

create or replace function public.touch_friend_streak_reaction()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.bump_friend_streak(new.sender_id, new.target_id);
  return new;
end;
$$;

drop trigger if exists reactions_touch_streak on public.map_reactions;
create trigger reactions_touch_streak
  after insert on public.map_reactions
  for each row execute function public.touch_friend_streak_reaction();

-- A streak only survives if it was touched today or yesterday; this clears the
-- stale ones so the UI does not have to special case them.
create or replace function public.expire_stale_streaks()
returns void language sql security definer set search_path = public as $$
  update public.friendships
     set streak_days = 0
   where streak_days > 0
     and (last_interaction_on is null
       or last_interaction_on < (now() at time zone 'utc')::date - 1);
$$;

-- ----------------------------------------------------------------------------
-- Push delivery. The triggers below are only created when pg_net is available,
-- because calling an Edge Function from a trigger needs it. Without pg_net the
-- app still works; friends just do not get notified while it is closed.
--
-- Before this does anything you must set the project URL and service key once:
--   select set_config('app.settings.supabase_url', 'https://xxx.supabase.co', false);
-- Persist them instead with:
--   alter database postgres set app.settings.supabase_url = 'https://xxx.supabase.co';
--   alter database postgres set app.settings.service_role_key = 'eyJ...';
-- ----------------------------------------------------------------------------
create or replace function public.notify_push(
  p_user_id uuid,
  p_title text,
  p_body text
) returns void language plpgsql security definer set search_path = public as $$
declare
  base_url text := current_setting('app.settings.supabase_url', true);
  service_key text := current_setting('app.settings.service_role_key', true);
begin
  if base_url is null or service_key is null then
    return;
  end if;
  if to_regproc('net.http_post') is null then
    return;
  end if;

  perform net.http_post(
    url := base_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object('user_id', p_user_id, 'title', p_title, 'body', p_body)
  );
exception when others then
  -- A failed notification must never roll back the message that caused it.
  return;
end;
$$;

create or replace function public.push_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  sender_name text;
  group_name text;
  member_id uuid;
begin
  select coalesce(nullif(display_name, ''), '@' || username)
    into sender_name from public.profiles where id = new.sender_id;

  if new.group_id is not null then
    select name into group_name from public.chat_groups where id = new.group_id;
    for member_id in
      select user_id from public.chat_group_members
      where group_id = new.group_id and user_id <> new.sender_id
    loop
      perform public.notify_push(
        member_id,
        coalesce(sender_name, 'Friend') || ' · ' || coalesce(group_name, 'Group chat'),
        left(coalesce(new.body, ''), 120)
      );
    end loop;
    return new;
  end if;

  perform public.notify_push(
    new.recipient_id,
    coalesce(sender_name, 'Friend'),
    case new.kind
      when 'wave' then 'waved at you 👋'
      when 'whats_up' then 'asked what you''re up to 👀'
      else left(coalesce(new.body, ''), 120)
    end
  );
  return new;
end;
$$;

drop trigger if exists messages_push on public.messages;
create trigger messages_push
  after insert on public.messages
  for each row execute function public.push_on_message();

-- Arrival notices fan out to everyone who can still see the mover's location.
create or replace function public.push_on_place_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  mover_name text;
  friend_id uuid;
begin
  select coalesce(nullif(display_name, ''), '@' || username)
    into mover_name from public.profiles where id = new.user_id;

  for friend_id in
    select case when f.requester_id = new.user_id then f.addressee_id else f.requester_id end
      from public.friendships f
     where f.status = 'accepted'
       and (f.requester_id = new.user_id or f.addressee_id = new.user_id)
  loop
    if public.shares_location_with(new.user_id, friend_id) then
      perform public.notify_push(
        friend_id,
        coalesce(mover_name, 'Friend'),
        (case new.kind when 'arrive' then 'arrived at ' else 'left ' end)
          || coalesce(nullif(new.label, ''), 'a place')
      );
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists place_events_push on public.place_events;
create trigger place_events_push
  after insert on public.place_events
  for each row execute function public.push_on_place_event();

-- ----------------------------------------------------------------------------
-- In-app account deletion. App Store guideline 5.1.1(v) requires this for any
-- app that lets users create an account, and deleting from auth.users needs
-- privileges the anon role does not have, hence security definer.
--
-- profiles.id cascades from auth.users and every other table cascades from
-- profiles, so one delete clears all of the user's rows. Avatars live in
-- storage and are keyed by path rather than a foreign key, so they go manually.
-- ----------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from storage.objects
   where bucket_id = 'avatars'
     and (storage.foldername(name))[1] = uid::text;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- These are security definer, so they must not be callable by anon.
revoke all on function public.my_heatmap(integer) from public, anon;
revoke all on function public.my_frequent_places(integer) from public, anon;
grant execute on function public.my_heatmap(integer) to authenticated;
grant execute on function public.my_frequent_places(integer) to authenticated;

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
    '#ff6847', '✨', 'Just joined Pinpop'
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
  '#ff6847', '✨', 'Just joined Pinpop'
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
do $$ begin alter publication supabase_realtime add table public.map_reactions;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.place_events;
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
do $$ begin alter publication supabase_realtime add table public.zones;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.chat_groups;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.chat_group_members;
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
union all select 'map_reactions table',
       case when to_regclass('public.map_reactions') is not null then 'ok' else 'MISSING' end
union all select 'best_friends table',
       case when to_regclass('public.best_friends') is not null then 'ok' else 'MISSING' end
union all select 'place_events table',
       case when to_regclass('public.place_events') is not null then 'ok' else 'MISSING' end
union all select 'push_tokens table',
       case when to_regclass('public.push_tokens') is not null then 'ok' else 'MISSING' end
union all select 'friendship streak columns',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'friendships' and column_name = 'streak_days')
       then 'ok' else 'MISSING' end
union all select 'delete_my_account()',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'delete_my_account') then 'ok' else 'MISSING' end
union all select 'footprint functions',
       case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('my_heatmap', 'my_frequent_places')) = 2
       then 'ok' else 'MISSING' end
union all select 'streak trigger',
       case when exists (select 1 from pg_trigger
         where tgname = 'messages_touch_streak' and not tgisinternal) then 'ok' else 'MISSING' end
union all select 'avatars storage bucket',
       case when exists (select 1 from storage.buckets where id = 'avatars') then 'ok' else 'MISSING' end
union all select 'avatars public read policy',
       case when exists (select 1 from pg_policies
         where schemaname = 'storage' and tablename = 'objects'
           and policyname = 'avatars are publicly readable')
       then 'ok' else 'MISSING' end
union all select 'places insert policy',
       case when exists (select 1 from pg_policies
         where schemaname = 'public' and tablename = 'places' and policyname = 'create user place')
       then 'ok' else 'MISSING' end
union all select 'zones table',
       case when to_regclass('public.zones') is not null then 'ok' else 'MISSING' end
union all select 'chat_groups table',
       case when to_regclass('public.chat_groups') is not null then 'ok' else 'MISSING' end
union all select 'chat_group_members table',
       case when to_regclass('public.chat_group_members') is not null then 'ok' else 'MISSING' end
union all select 'messages.group_id column',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'messages' and column_name = 'group_id')
       then 'ok' else 'MISSING' end
union all select 'is_group_member()',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'is_group_member') then 'ok' else 'MISSING' end
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
union all select 'highlights.lat column',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'highlights' and column_name = 'lat')
       then 'ok' else 'MISSING' end
union all select 'invites table',
       case when to_regclass('public.invites') is not null then 'ok' else 'MISSING' end
union all select 'redeem_invite()',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'redeem_invite') then 'ok' else 'MISSING' end
union all select 'reaction streak trigger',
       case when exists (select 1 from pg_trigger
         where tgname = 'reactions_touch_streak' and not tgisinternal) then 'ok' else 'MISSING' end
union all select 'streak repair columns',
       case when exists (select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'friendships' and column_name = 'streak_grace_value')
       then 'ok' else 'MISSING' end
union all select 'suggested_friends()',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'suggested_friends') then 'ok' else 'MISSING' end
order by item;
