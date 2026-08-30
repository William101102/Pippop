-- Apply ONLY after review_duplicate_friendships.sql shows zero rows
-- or after a reviewed cleanup migration.

-- create unique index if not exists friendships_pair_unique
--   on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
