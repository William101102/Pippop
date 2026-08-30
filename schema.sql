-- 近旁 (Zenly-style friend map) — Supabase schema
-- Paste this whole file into your Supabase project's SQL Editor and click Run.

-- 用户资料(好友能看到的公开信息)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null,
  avatar_color text not null default '#ff6f61',
  status_emoji text not null default '🏠',
  status_text text not null default '在家',
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles readable by authenticated users"
  on public.profiles for select using (auth.role() = 'authenticated');
create policy "users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);
create policy "users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- 好友关系(请求/接受)
create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique (requester_id, addressee_id)
);
alter table public.friendships enable row level security;
create policy "see own friendships"
  on public.friendships for select
  using (auth.uid() = requester_id or auth.uid() = addressee_id);
create policy "create friend request"
  on public.friendships for insert with check (auth.uid() = requester_id);
create policy "respond to friend request"
  on public.friendships for update using (auth.uid() = addressee_id);

-- 实时位置(只有互相加过好友才能看到对方)
create table public.locations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);
alter table public.locations enable row level security;
create policy "view own location"
  on public.locations for select using (auth.uid() = user_id);
create policy "view friends location"
  on public.locations for select
  using (exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = locations.user_id)
        or (f.addressee_id = auth.uid() and f.requester_id = locations.user_id))
  ));
create policy "upsert own location"
  on public.locations for insert with check (auth.uid() = user_id);
create policy "update own location"
  on public.locations for update using (auth.uid() = user_id);

-- 私信(仅限好友之间)
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.messages enable row level security;
create policy "view own messages"
  on public.messages for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);
create policy "send messages to friends"
  on public.messages for insert
  with check (auth.uid() = sender_id and exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = recipient_id)
        or (f.addressee_id = auth.uid() and f.requester_id = recipient_id))
  ));

-- 打开实时同步
alter publication supabase_realtime add table public.locations;
alter publication supabase_realtime add table public.friendships;
alter publication supabase_realtime add table public.messages;
