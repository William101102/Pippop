-- Streaks now also bump from throws (map_reactions), not just messages, and
-- invite links redeem straight into a mutual friendship (no separate accept
-- step) via a security-definer RPC. See backend/supabase/setup.sql for the
-- authoritative, always-current version of this schema.

create or replace function public.bump_friend_streak(p_a uuid, p_b uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'utc')::date;
begin
  update public.friendships f
     set streak_days = case
           when f.last_interaction_on = today then f.streak_days
           when f.last_interaction_on = today - 1 then f.streak_days + 1
           else 1
         end,
         last_interaction_on = today
   where f.status = 'accepted'
     and ((f.requester_id = p_a and f.addressee_id = p_b)
       or (f.addressee_id = p_a and f.requester_id = p_b));

  update public.friendships f
     set longest_streak = f.streak_days
   where f.streak_days > f.longest_streak
     and ((f.requester_id = p_a and f.addressee_id = p_b)
       or (f.addressee_id = p_a and f.requester_id = p_b));
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
