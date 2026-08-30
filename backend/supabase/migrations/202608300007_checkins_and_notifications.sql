-- Check-ins, unread message tracking and per-friend Ghost Mode support.
-- Apply on a development Supabase project first.

-- ---------------------------------------------------------------------------
-- Places: the prototype only granted SELECT, so user check-ins were rejected.
-- ---------------------------------------------------------------------------
alter table public.places add column if not exists created_by uuid references public.profiles(id) on delete set null;
create index if not exists places_lat_lng_idx on public.places (lat, lng);
create index if not exists places_created_by_idx on public.places (created_by);

drop policy if exists "create user place" on public.places;
create policy "create user place" on public.places for insert
  with check (auth.uid() = created_by and source = 'user');

drop policy if exists "update own place" on public.places;
create policy "update own place" on public.places for update
  using (auth.uid() = created_by) with check (auth.uid() = created_by);

drop policy if exists "delete own place" on public.places;
create policy "delete own place" on public.places for delete
  using (auth.uid() = created_by);

-- ---------------------------------------------------------------------------
-- Messages: recipients need to be able to stamp read_at, and unread counting
-- needs an index. Policies are named distinctly so they coexist with whatever
-- the original prototype schema created.
-- ---------------------------------------------------------------------------
create index if not exists messages_unread_idx
  on public.messages (recipient_id, read_at)
  where read_at is null;
create index if not exists messages_pair_time_idx
  on public.messages (sender_id, recipient_id, created_at desc);

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

-- ---------------------------------------------------------------------------
-- Visits: friends browsing the nearby panel need the place row joined in.
-- ---------------------------------------------------------------------------
create index if not exists visits_place_idx on public.visits (place_id, arrived_at desc);

-- ---------------------------------------------------------------------------
-- Realtime: friend requests and messages drive the notification badge.
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.visits;
exception when duplicate_object then null; end $$;
