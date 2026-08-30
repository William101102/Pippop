-- Ensure every Auth user receives a matching application profile.
-- Usernames are normalized and receive a short ID suffix if already taken.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  requested_username text;
  safe_username text;
  chosen_name text;
begin
  requested_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', ''), '[^a-z0-9_]', '', 'g'));
  if char_length(requested_username) < 3 then
    requested_username := 'user_' || left(replace(new.id::text, '-', ''), 8);
  end if;

  safe_username := requested_username;
  if exists (select 1 from public.profiles where username = safe_username) then
    safe_username := left(requested_username, 20) || '_' || left(replace(new.id::text, '-', ''), 5);
  end if;

  chosen_name := nullif(trim(new.raw_user_meta_data->>'display_name'), '');
  insert into public.profiles (
    id, username, display_name, avatar_color, status_emoji, status_text
  ) values (
    new.id,
    safe_username,
    coalesce(chosen_name, split_part(coalesce(new.email, safe_username), '@', 1)),
    '#ff6847',
    '✨',
    '刚刚加入 Pinpop'
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Repair Auth users created before the trigger existed.
insert into public.profiles (id, username, display_name, avatar_color, status_emoji, status_text)
select
  u.id,
  'user_' || left(replace(u.id::text, '-', ''), 8),
  split_part(coalesce(u.email, 'New friend'), '@', 1),
  '#ff6847',
  '✨',
  '刚刚加入 Pinpop'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict do nothing;
