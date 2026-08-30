# Pinpop

A privacy-first social map inspired by the playful parts of Zenly. Pinpop is now split into a
React/TypeScript web frontend and a versioned Supabase backend.

## Included in the web foundation

- Original Pinpop app icon and PWA icon set
- Photo avatar upload through a locked-down Supabase Storage bucket
- Photo-based map pins, profile cards and friend rows
- Playful social-map visual system for desktop and mobile
- Responsive live friend map and presence cards
- Friend discovery, messages and quick reactions
- What's Up interaction entry point
- Precise, blurred and frozen Ghost Mode UI
- Places, check-ins and personal-world foundations
- Footprint/history data model and private analytics UI
- Hardened database policies, blocks and expiring highlights
- Preview mode so UI work is testable without production data

## Structure

```text
src/                         React web application
backend/supabase/migrations/ Database schema and RLS policies
.github/workflows/           Build and GitHub Pages deployment
```

## Local development

```bash
cp .env.example .env.local
npm install
npm run dev
```

Add the public Supabase URL and anon key to `.env.local`. Never expose a service-role key.

Run the Supabase migrations in filename order on a development project before production. The
avatar migration creates a public-read `avatars` bucket with owner-only writes. The auth bootstrap
migration creates a profile for new Auth users and repairs older Auth users missing a profile.

## Deployment

Set repository variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, then enable GitHub
Pages with GitHub Actions as its source. Every push to `main` builds and deploys `dist/`.

## Product roadmap

The browser cannot provide dependable background location or native push notifications.
Those features will be delivered by a React Native/Expo mobile client against this same backend.
