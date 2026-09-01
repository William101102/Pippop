# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Pinpop** — a Zenly-style social map. Friends appear live on a map, you can wave,
chat, throw emoji, and control exactly how precisely each friend sees you.

One React codebase ships as **both** the website and the iOS app
(`com.pinpop.app`, via Capacitor). GitHub Pages hosts only the public/invite
surface — it is not a separate marketing site.

- Repo: `William101102/zenly-app` · branch `main`
- Product name is **Pinpop**; the repo name (`zenly-app`) is historical. Use
  "Pinpop" in all user-facing copy.

## Stack

| Layer | Choice |
|---|---|
| UI | React 18 + TypeScript (strict), Vite 6 |
| Map | Leaflet 1.9 (`MapCanvas.tsx`), OSM tiles |
| Backend | Supabase (Postgres + Auth + Realtime + Storage + Edge Functions) |
| Native shell | Capacitor 8 (iOS) — background geolocation, push, haptics, share |
| Icons | lucide-react · Fonts: DM Sans + Fredoka |
| Tests | Vitest (unit only, on pure logic in `src/lib`) |

## Commands

```
npm install
npm run dev          # http://127.0.0.1:5173/?preview=1
npm run typecheck    # tsc -b --pretty false
npm run test         # vitest run
npm run build        # tsc -b && vite build && copy 404.html
```

iOS (needs macOS + full Xcode + Apple Developer Program):

```
npm run ios:add      # once — creates ios/, writes Info.plist + icons
npm run ios:sync     # after ANY web change — rebuild web assets into ios/
npm run ios:open     # opens Xcode
```

`ios/` is generated and gitignored. Never hand-edit it; re-run `ios:sync`.

**Always run `npm run typecheck && npm run test && npm run build` before
committing.** There is no CI gate that will catch a break for you.

## Preview mode

`?preview=1` loads demo friends around Santa Monica with **no account and no
Supabase**. It is the primary way to develop and to review UI changes.

Preview mode is not cosmetic — it is load-bearing in the code:

- `preview` short-circuits every write path. Guard any new network write with
  it, or the demo will try to hit Supabase.
- `isUserUuid(profile.id)` is the second guard: demo profiles have non-UUID ids.
  Both checks usually appear together — keep that pattern.
- A previously-signed-in device can restore a real session *after* preview
  flips on. The location watcher explicitly checks `preview` for this reason
  (see the long comment above the `watchLocation` effect in `App.tsx`) —
  removing that check reintroduces the "490 km away, riding a bike" bug.

## Directory map

```
src/
  App.tsx              ~1900 lines. Shell, map, panel routing, most state.
  components/          Presentational panels & sheets
  hooks/               useAuth, useFriends, useMessages, useRealtime,
                       useBattery, useDraggableSheet, useSignificantPlaces
  services/            One module per Supabase table/domain. All DB access
                       goes through here — components never call supabase directly.
  lib/                 Pure logic + platform adapters (geo, streak, cluster,
                       geofence, places, location, native, push). Tests live here.
  dev/demo.ts          Preview-mode fixtures
backend/supabase/      setup.sql (idempotent, run this) + migrations/ + fixes
ios-setup/             Info.plist additions, icon generation, App Store notes
legacy/                Pre-React implementation. Reference only — do not extend.
```

## Domain concepts you must understand before changing things

**Ghost Mode** — three privacy levels (`precise` / `blurred` ≈0.2–1.2 km random
offset / `frozen` = pinned to last shared point), settable globally *and*
per-friend, stored in `location_privacy` (`owner_id`, `viewer_id`).
The self row is `owner_id === viewer_id`.

> **Masking is server-side.** Friends read the `friend_locations` **view**, which
> applies the blur/freeze in SQL. The raw `locations` table is never exposed to
> friends by RLS. Never bypass `friend_locations` — even when Realtime hands you
> a raw `locations` row, re-read through the view (`handleFriendLocation` does
> this deliberately).

**Location upload is throttled** by `createFixGate()` in `lib/location.ts`:
a fix is only persisted after ≥25 m of movement **or** ≥45 s. Every persisted fix
fans out over Realtime to all friends, so do not remove the gate — it is what
keeps battery and quota sane. `frozen` mode returns before persisting at all.

**Streaks** — consecutive days two friends interacted (message or throw).
`lib/streak.ts` is the client's honest view: the DB only corrects `streak_days`
on the *next* interaction, so the client treats a stale value as already broken.
There is a TikTok-style **repair** window (miss one day → 3 consecutive days
restores it). Milestones: 3/7/14/30/50/100/200/365.

**Highlights** — 24 h stories; optionally attach location to also drop a
circular story pin on the map (Snap Map style). Expiry is enforced server-side.

**Zenlands (`zones`)** — user-named, friend-visible areas with a radius.
Arrive/leave detection runs on the *mover's* device (`lib/geofence.ts`) with
hysteresis (leave radius > arrive radius) so a drifting fix cannot flap.

**Significant places / footprints** — private to the owner. Overnight-spot
detection (i.e. "home") is deliberately never shared.

**Invite links** — `?t=<uuid>` token mints an instant mutual friendship, no
accept step. Legacy `?add=username` still resolves. Both parsed in `lib/geo.ts`.

## Conventions

- **UI copy is English.** (The codebase was localized from Chinese; some
  comments and SQL remain Chinese — that is fine, user-facing strings are not.)
- **All DB access lives in `src/services/`.** Components and hooks call services.
- **Pure logic goes in `src/lib/` and gets a test.** That is where Vitest looks.
- Styling is one hand-written `src/styles.css` with CSS custom properties on
  `:root`. There is no CSS framework. Respect the existing tokens
  (`--coral --pink --violet --ink --muted --safe-top --safe-bottom --dock-h`).
- Safe-area insets matter — this ships on notched iPhones. Anything anchored to
  a screen edge must account for `--safe-top` / `--safe-bottom`.
- User-facing feedback goes through the single `notify()` choke point in
  `App.tsx` (it also drives haptics).

## Known traps

- **`src/components/BottomDock.tsx` is dead code** — it is never imported. The
  real dock is inline in `App.tsx` (~line 1351). Editing BottomDock changes
  nothing. It should probably be deleted.
- **`.person-card` height is deliberately capped** with
  `max-height: calc(100dvh - var(--safe-top) - var(--pc-bottom))` plus a flex
  column whose `.person-card-body` scrolls. This is the fix for the card growing
  up behind the status bar. Do not replace it with a guessed pixel offset —
  that is exactly the bug it replaced.
- **Do not keep this repo inside an iCloud-synced folder** (Desktop/Documents
  with iCloud Drive on). iCloud offloads `.git` metadata to `.icloud`
  placeholders and git then reports `fatal: not a git repository`. Keep it
  somewhere like `~/dev/`.
- Interactive zsh does **not** treat `#` as a comment. Command blocks pasted
  into a terminal must not contain `#` comment lines.
- `problem.md` is a **stale** review list — several P1 items in it (frozen-coord
  leak, unthrottled uploads) were already fixed by later refactors. Verify
  against the code before acting on it.

## Backend

Run `backend/supabase/setup.sql` in the Supabase SQL editor. It is idempotent —
re-run it after pulling so the public-avatar policy and the 0.2–1.2 km blur stay
current. Individual `migrations/` exist for history; `setup.sql` is the source
of truth for a fresh project.

Env (`.env.local`, never commit):

| Variable | Notes |
|---|---|
| `VITE_SUPABASE_URL` | also a GitHub Actions var |
| `VITE_SUPABASE_ANON_KEY` | anon key only — never the service-role key |
| `VITE_PUBLIC_APP_URL` | optional; invite links inside the installed app |

## Deferred work (do not start these without asking)

Feature-level, tracked in `problem.md`: unread `read_at` badge, making the World
panel's weekly-distance real, Places/POI, PWA service worker, backend rate
limiting, private avatar bucket, broader test coverage.
