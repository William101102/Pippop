# Pinpop backend

Pinpop uses Supabase as its independent backend: PostgreSQL, Auth, Row Level Security,
Realtime, Storage and future Edge Functions. The frontend never receives a service-role key.

## Apply migrations

Run files in `supabase/migrations` in timestamp order through the Supabase SQL editor or CLI.
The first migration upgrades the original prototype schema without deleting existing data.

Before production, configure separate development and production Supabase projects, enable
email verification, set allowed redirect URLs, create a private avatar/highlight storage bucket,
and add rate limiting through an Edge Function for friend requests and messages.

## Mobile path

The future iOS/Android client will use the same tables and RLS policies. Native-only services
(background location, push notifications, contacts and media upload) belong in Supabase Edge
Functions plus a React Native/Expo client, not in the web application.
