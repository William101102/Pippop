-- Review duplicate friendship rows BEFORE applying friendships_pair_unique.
-- Run in Supabase SQL editor on a dev/staging project first.
--
-- This script only reports duplicates; it does not delete anything.

select
  least(requester_id, addressee_id) as user_a,
  greatest(requester_id, addressee_id) as user_b,
  count(*) as row_count,
  array_agg(id order by created_at) as friendship_ids,
  array_agg(status order by created_at) as statuses
from public.friendships
group by 1, 2
having count(*) > 1
order by row_count desc;

-- After manual review, you may keep the oldest accepted row (or newest pending)
-- and delete extras in a separate, reviewed migration.
