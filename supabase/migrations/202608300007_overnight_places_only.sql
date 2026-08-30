-- Retire Home/Work detection. Keep only private overnight-place counts.
-- Existing owner-only RLS policies remain unchanged.

do $$
begin
  if to_regclass('public.significant_places') is not null then
    delete from public.significant_places where kind in ('home', 'work');

    alter table public.significant_places
      drop constraint if exists significant_places_kind_check;
    alter table public.significant_places
      add constraint significant_places_kind_check check (kind = 'overnight');
  end if;
end
$$;
