# Pinpop

Zenly-style friend location map — React + TypeScript + Vite frontend with Supabase backend.

## Stack

- **Frontend:** React 18, TypeScript, Vite, Leaflet
- **Backend:** Supabase (Auth, Postgres, Realtime)
- **Deploy:** GitHub Pages via `.github/workflows/pages.yml`

## Quick start

```bash
cp .env.example .env.local
# fill VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

## Scripts

| Command | Purpose |
|---|---|
| `npm run dev` | Local dev server |
| `npm run build` | Production build to `dist/` |
| `npm run typecheck` | TypeScript check |
| `npm run preview` | Preview production build |

## Environment variables

Set in `.env.local` locally and as **GitHub repository variables** for Pages:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Never commit a service-role key.

## Database

1. Run original [`schema.sql`](./schema.sql) on a **development** Supabase project.
2. Review [`backend/supabase/scripts/review_duplicate_friendships.sql`](./backend/supabase/scripts/review_duplicate_friendships.sql).
3. Apply migrations in [`backend/supabase/migrations/`](./backend/supabase/migrations/) **on dev first**.
4. Ghost Mode enforcement lives in `202608300002_ghost_mode_locations.sql` (`friend_locations` view).

The legacy single-file app is preserved at [`legacy/index.html`](./legacy/index.html).

## Features ported from legacy

- Sign up / sign in / profile completion
- Friend search, requests, accept/decline, invite links (`?add=username`)
- Live location + Realtime updates
- 1:1 chat and waves
- Status cycling
- Share self (add-friend card) vs share friend (friend detail card)
- Preview mode with demo data
- Ghost Mode UI + server-side masking (after migration)

## Live demo

https://william101102.github.io/zenly-app/
