# Pinpop backend

Pinpop uses Supabase as its independent backend: PostgreSQL, Auth, Row Level Security,
Realtime, Storage and future Edge Functions. The frontend never receives a service-role key.

## Apply migrations

Run files in `supabase/migrations` in timestamp order through the Supabase SQL editor or CLI:

1. `202608300001_pinpop_core.sql` — schema extensions
2. `202608300002_profile_avatars.sql` — public `avatars` bucket with owner-only writes
3. `202608300003_auth_profile_bootstrap.sql` — auto-create profiles on signup (replaces any existing `on_auth_user_created` trigger)
4. `202608300004_ghost_mode_locations.sql` — server-side ghost mode (dev only until verified)
5. `202608300005_friendships_pair_unique.sql` — optional; review duplicates first
6. `202608300006_significant_places.sql` — private location history and significant places
7. `202608300007_overnight_places_only.sql` — remove Home/Work rows and retain overnight counts only

Or from the repo root after `npx supabase login`:

```bash
bash scripts/supabase-push.sh
```

Confirm the existing `profiles` schema matches the bootstrap migration before production.

Before production, configure separate development and production Supabase projects, enable
email verification, set allowed redirect URLs, create a private avatar/highlight storage bucket,
and add rate limiting through an Edge Function for friend requests and messages.

## Mobile path

The future iOS/Android client will use the same tables and RLS policies. Native-only services
(background location, push notifications, contacts and media upload) belong in Supabase Edge
Functions plus a React Native/Expo client, not in the web application.
