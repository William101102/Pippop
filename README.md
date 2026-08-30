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

Your project: **nzqgkbibuqnfbxfarswu** (`https://nzqgkbibuqnfbxfarswu.supabase.co`)

### First-time CLI setup (you run locally)

```bash
npx supabase login
bash scripts/supabase-push.sh
```

This links the repo and runs `supabase db push` for migrations in `supabase/migrations/`.

> If tables already exist from manual `schema.sql`, only the **new** migrations (pinpop_core, ghost_mode) will apply.

### Manual alternative

1. Run original [`schema.sql`](./schema.sql) if starting fresh.
2. Paste migrations from [`supabase/migrations/`](./supabase/migrations/) into Supabase SQL Editor (dev project first).

### Email signup blocked?

In Supabase Dashboard → **Authentication → Providers → Email**, turn off **Confirm email** for easier testing.

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
