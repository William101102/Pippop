-- Significant places (overnight spots, home, work) — private to the owner.
-- Data source: location_history rows written by the client while the app is open.

-- Raw visited points, one row per throttled location fix.
create table if not exists public.location_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  recorded_at timestamptz not null default now(),
  -- Grid cell (~50 m) for cheap clustering on the client.
  cell_lat bigint not null,
  cell_lng bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists location_history_user_time_idx
  on public.location_history (user_id, recorded_at desc);

alter table public.location_history enable row level security;
create policy "manage own location history"
  on public.location_history for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Client-computed significant places (deduped, one row per detected place).
create table if not exists public.significant_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('overnight', 'home', 'work')),
  lat double precision not null,
  lng double precision not null,
  label text not null default '',
  -- overnight spots: number of distinct nights detected; work: minutes stayed.
  score numeric not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, kind, cell_lat, cell_lng)
);

alter table public.significant_places enable row level security;
create policy "manage own significant places"
  on public.significant_places for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
