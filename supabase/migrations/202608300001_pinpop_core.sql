-- Pinpop core schema. Safe to run after the original schema.sql.
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists bio text not null default '';
alter table public.profiles add column if not exists battery_level smallint check (battery_level between 0 and 100);
alter table public.profiles add column if not exists is_charging boolean not null default false;
alter table public.profiles add column if not exists last_active_at timestamptz not null default now();

alter table public.locations add column if not exists accuracy double precision;
alter table public.locations add column if not exists altitude double precision;
alter table public.locations add column if not exists speed double precision;
alter table public.locations add column if not exists heading double precision;

alter table public.messages add column if not exists kind text not null default 'text'
  check (kind in ('text','emoji','wave','image','location','whats_up'));
alter table public.messages add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.messages add column if not exists read_at timestamptz;

create table if not exists public.location_privacy (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid references public.profiles(id) on delete cascade,
  mode text not null default 'precise' check (mode in ('precise','blurred','frozen')),
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
  accuracy double precision,
  recorded_at timestamptz not null default now()
);
create index if not exists location_history_user_time_idx on public.location_history(user_id, recorded_at desc);

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

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  arrived_at timestamptz not null default now(),
  departed_at timestamptz,
  visibility text not null default 'private' check (visibility in ('private','friends','public')),
  note text,
  check (departed_at is null or departed_at >= arrived_at)
);
create index if not exists visits_user_time_idx on public.visits(user_id, arrived_at desc);

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
  status text not null default 'pending' check (status in ('pending','answered','declined','expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 hours'),
  check (sender_id <> recipient_id)
);

alter table public.location_privacy enable row level security;
alter table public.location_history enable row level security;
alter table public.places enable row level security;
alter table public.visits enable row level security;
alter table public.highlights enable row level security;
alter table public.blocks enable row level security;
alter table public.whats_up_requests enable row level security;

-- Harden policies inherited from the prototype.
drop policy if exists "create friend request" on public.friendships;
create policy "create friend request" on public.friendships for insert
  with check (auth.uid() = requester_id and requester_id <> addressee_id and status = 'pending');
drop policy if exists "respond to friend request" on public.friendships;
create policy "respond to friend request" on public.friendships for update
  using (auth.uid() = addressee_id and status = 'pending')
  with check (auth.uid() = addressee_id and status in ('accepted','declined'));

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile" on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "update own location" on public.locations;
create policy "update own location" on public.locations for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "manage own privacy" on public.location_privacy for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "read own history" on public.location_history for select using (auth.uid() = user_id);
create policy "write own history" on public.location_history for insert with check (auth.uid() = user_id);
create policy "delete own history" on public.location_history for delete using (auth.uid() = user_id);
create policy "authenticated read places" on public.places for select using (auth.role() = 'authenticated');
create policy "read visible visits" on public.visits for select using (
  auth.uid() = user_id or (visibility = 'friends' and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester_id = auth.uid() and f.addressee_id = visits.user_id) or
       (f.addressee_id = auth.uid() and f.requester_id = visits.user_id)))));
create policy "manage own visits" on public.visits for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "read friend highlights" on public.highlights for select using (
  auth.uid() = user_id or (expires_at > now() and exists (
    select 1 from public.friendships f where f.status = 'accepted' and
      ((f.requester_id = auth.uid() and f.addressee_id = highlights.user_id) or
       (f.addressee_id = auth.uid() and f.requester_id = highlights.user_id)))));
create policy "manage own highlights" on public.highlights for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "manage own blocks" on public.blocks for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);
create policy "see own whats up" on public.whats_up_requests for select using (auth.uid() in (sender_id, recipient_id));
create policy "send whats up to friend" on public.whats_up_requests for insert with check (
  auth.uid() = sender_id and exists (select 1 from public.friendships f where f.status = 'accepted' and
    ((f.requester_id = auth.uid() and f.addressee_id = recipient_id) or
     (f.addressee_id = auth.uid() and f.requester_id = recipient_id))));
create policy "answer whats up" on public.whats_up_requests for update
  using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

-- Reject oversized/blank chat payloads at the database boundary.
alter table public.messages drop constraint if exists messages_body_length;
alter table public.messages add constraint messages_body_length check (char_length(trim(body)) between 1 and 2000);

-- Prevent duplicate friendships regardless of direction.
create unique index if not exists friendships_pair_unique
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

do $$ begin
  alter publication supabase_realtime add table public.highlights;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.whats_up_requests;
exception when duplicate_object then null; end $$;
