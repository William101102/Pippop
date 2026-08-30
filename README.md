# Pinpop

A Zenly-style friend location map — one HTML file + [Supabase](https://supabase.com). Real accounts, friends, live locations, and chat. No fake data.

**Live demo:** https://william101102.github.io/zenly-app/

**Custom domain (when you buy it):** https://pinpop.app

## What it does

- Email sign up / sign in (Supabase Auth)
- Live map with you and your friends (browser GPS + Supabase Realtime)
- Search and add friends by ID or name; they must accept first
- Only friends can see each other's location (enforced by database RLS)
- Switch your status (🏠 home / 💼 work / 🍔 eating / 🎧 chilling / 🚶 walking)
- 1:1 chat and quick wave 👋
- Bottom friend sheet — swipe up like the real Zenly app

## Tech stack

| Part | Choice |
|---|---|
| UI | Vanilla HTML / CSS / JS (no build step) |
| Map | Leaflet + OpenStreetMap (free, no API key) |
| Backend | Supabase (Postgres + Auth + Realtime) |
| Location | Browser Geolocation API |

## Run locally

1. Run [`schema.sql`](./schema.sql) in your Supabase SQL Editor.
2. Turn off email confirmation for testing: **Authentication → Providers → Email → disable "Confirm email"**.
3. Open `index.html` in a browser (double-click is fine).
4. Register two accounts, add each other as friends, allow location permission.

Supabase keys are already in `index.html`. The `anon` key is meant to be public.

## Deploy to GitHub Pages (free HTTPS)

This repo includes [`.github/workflows/pages.yml`](./.github/workflows/pages.yml). After you push to `main`:

1. Open **GitHub → zenly-app → Settings → Pages**
2. Under **Build and deployment → Source**, choose **GitHub Actions**
3. Wait ~1 minute for the workflow to finish
4. Visit **https://william101102.github.io/zenly-app/**

> Geolocation only works on **HTTPS** (or `localhost`). GitHub Pages gives you HTTPS for free.

### One-time check

Go to **Actions** tab → confirm the "Deploy to GitHub Pages" workflow succeeded (green check).

## Custom domain: `https://pinpop.app`

**Pinpop** = pin (on the map) + pop (playful, Zenly-like). Short, easy to remember, works as a URL.

To use `https://pinpop.app` instead of the long `github.io/zenly-app` path:

### 1. Buy the domain (~$10–15/year)

Buy **pinpop.app** (or **pinpop.io**, **getpinpop.com**, etc.) from:

- [Cloudflare Registrar](https://www.cloudflare.com/products/registrar/)
- [Namecheap](https://www.namecheap.com)
- [Porkbun](https://porkbun.com)

Search `pinpop.app` and buy if available. If taken, try `pinpop.io` or `usepinpop.com`.

### 2. Point DNS to GitHub Pages

In your domain registrar's DNS settings:

| Type | Name | Value |
|---|---|---|
| `A` | `@` | `185.199.108.153` |
| `A` | `@` | `185.199.109.153` |
| `A` | `@` | `185.199.110.153` |
| `A` | `@` | `185.199.111.153` |
| `CNAME` | `www` | `william101102.github.io` |

(Cloudflare: set proxy to **DNS only** / grey cloud for the A records.)

### 3. Tell GitHub your domain

```bash
# In the repo root, create CNAME (copy from the example):
cp CNAME.example CNAME
# Edit CNAME if you bought a different domain, e.g. pinpop.io
git add CNAME
git commit -m "Add custom domain"
git push
```

Then in **Settings → Pages → Custom domain**, enter `pinpop.app` (or your domain) and enable **Enforce HTTPS**.

After DNS propagates (5 min – 48 hrs), the app runs at **https://pinpop.app**.

### 4. Add domain in Supabase (if auth redirects break)

Supabase → **Authentication → URL Configuration** → add:

- `https://pinpop.app`
- `https://william101102.github.io/zenly-app`

## Test the full flow

1. Open the live URL on your phone or laptop
2. Register with two different emails
3. Allow location when prompted
4. Search the other account's ID and send a friend request
5. Accept on the other account
6. You should see each other move on the map in real time

## Known limits

- Friend requests can duplicate if both users send at once (harmless)
- No unread message count — only a toast on new messages
- Map uses default OpenStreetMap tiles, not Zenly's candy-colored style
