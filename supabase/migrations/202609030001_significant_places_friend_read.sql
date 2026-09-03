-- Let friends see where you sleep — the "Night place"/"Home" pin the map
-- now draws. significant_places has been owner-only since
-- 202608300007_overnight_places_only.sql scrubbed the old home/work
-- detection down to a private overnight-only count; this reopens read
-- access to friends who already share your live location, using the same
-- rule zones and place_events already trust (shares_location_with). A
-- slow-changing night-place pin is no more exposed than the live dot those
-- same friends already see every day.
--
-- "manage own significant places" (for all) already covers select for the
-- owner; this is a second, additive select policy for everyone else —
-- Postgres ORs permissive policies together per command, so writes are
-- untouched.
drop policy if exists "friends read significant places" on public.significant_places;
create policy "friends read significant places" on public.significant_places for select using (
  auth.uid() = user_id or public.shares_location_with(user_id, auth.uid())
);
