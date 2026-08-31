-- Streaks now also bump from throws (map_reactions), not just messages, and
-- invite links redeem straight into a mutual friendship (no separate accept
-- step) via a security-definer RPC. See backend/supabase/setup.sql for the
-- authoritative, always-current version of this schema.

-- Missing exactly one day is forgivable: one repair shot, three consecutive
-- days back restores the streak as if it never broke. Missing more than one
-- day, or missing again mid-repair, is a clean reset.
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
      continue;
    end if;

    gap := case when rec.last_interaction_on is null then null else today - rec.last_interaction_on end;

    if gap = 1 then
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
      new_grace_value := coalesce(rec.streak_days, 0);
      new_grace_days := 1;
      new_streak := 1;
    else
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

-- Invite-link tokens.
create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  use_count integer not null default 0
);
create index if not exists invites_owner_idx on public.invites (owner_id);

alter table public.invites enable row level security;
drop policy if exists "manage own invites" on public.invites;
create policy "manage own invites" on public.invites for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

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
