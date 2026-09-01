# Pinpop — native iOS (vertical slice)

A SwiftUI foundation for the native Pinpop app. This is **not** a port of every
screen — it is the thin vertical slice that proves the parts the web build
cannot do, wired end to end against the same Supabase backend:

- Sign in with Apple **and** Google (see the 4.8 note below)
- MapKit map with live friend pins
- Background location with the same upload throttle as the web app
- The four native interactions: **UWB bump**, **shake**, **knock**, **charge-and-throw**
- **Live Activity + Dynamic Island** showing live bump distance, and a
  home-screen **Nearby friends** widget

> **This code has never been compiled.** It was written without access to Xcode
> or a macOS toolchain. The structure, APIs and architecture are sound, but
> expect to fix a handful of signature and import details on the first build.
> Treat it as a strong first draft, not a shipping binary.

## Setup

```
brew install xcodegen
cd ios-native
cp Sources/Config/Secrets.example.xcconfig Sources/Config/Secrets.xcconfig
```

Fill in `Secrets.xcconfig`, then:

```
xcodegen generate
open Pinpop.xcodeproj
```

In Xcode: set your Team under Signing & Capabilities, and set **both** Debug and
Release configurations to use `Secrets.xcconfig`
(Project → Info → Configurations).

Add `Sources/Config/Secrets.xcconfig` to `.gitignore`. It holds your keys.

### Capabilities to enable

| Capability | Where | Why |
|---|---|---|
| Sign in with Apple | app | Guideline 4.8 — mandatory because Google is offered |
| Background Modes → Location updates | app | keeps the map live when backgrounded |
| Background Modes → Remote notifications | app | pushes for waves and requests |
| Push Notifications | app | same |
| **App Groups** (`group.com.pinpop.app`) | **app + widget** | the widget reads its snapshot from the shared container |

Create the App Group once in the Developer portal, then tick it on **both** the
`Pinpop` and `PinpopWidgets` targets. If the identifier differs from
`group.com.pinpop.app`, change `NearbySnapshot.appGroup` and both
`.entitlements` files to match — a mismatch fails silently as an empty widget.

### Backend

Uses the existing Supabase project. Two additions the web app doesn't have:

```sql
-- Real-world meetings detected over UWB.
create table if not exists public.bumps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  friend_id uuid not null references auth.users on delete cascade,
  happened_at timestamptz not null default now()
);
alter table public.bumps enable row level security;

create policy "insert own bumps" on public.bumps
  for insert with check (auth.uid() = user_id);
create policy "read own bumps" on public.bumps
  for select using (auth.uid() = user_id or auth.uid() = friend_id);

-- Throw strength, so the receiving client can scale its celebration.
alter table public.map_reactions
  add column if not exists power double precision default 0.5;
```

Also add the Apple and Google providers in Supabase → Authentication → Providers.

## The interactions

| Interaction | Implementation | Notes |
|---|---|---|
| **Bump to meet** | `BumpService` — `NearbyInteraction` + `MultipeerConnectivity` | iPhone 11+. Both people need the screen open. MC is only used to swap `NIDiscoveryToken`s; ranging is UWB |
| **Shake** | `UIWindow.motionEnded` republished as a notification, `.onShake { }` | Debounced to 1.2 s |
| **Knock** | `KnockDetector` via `CMMotionManager` | See the caveat below |
| **Charge & throw** | `ThrowButton` + `Haptics.startCharge` | Core Haptics intensity ramp; power feeds the flight animation |
| **Live Activity** | `BumpLiveActivity` + `BumpActivityController` | Dynamic Island shows live distance while you walk toward each other |

### Live Activity update budget

`NISession` reports several times a second; ActivityKit is not built for that
and will throttle an activity that pushes at that rate.
`BumpActivityController` therefore rate-limits to **one update per second** and
skips updates where the distance moved less than **0.25 m** — phase changes
(`searching → tracking → met`) always go through immediately, because those are
the moments that matter. If you raise the cadence, raise it here, and keep
`NSSupportsLiveActivitiesFrequentUpdates` in mind rather than removing the gate.

The activity ends `.immediate` on cancel and lingers 6 s after a successful
bump so the celebration is visible.

### The Back Tap caveat — read this

iOS's real **Back Tap** (Settings → Accessibility → Touch → Back Tap) can only
be bound to system actions and **Shortcuts**. A third-party app *cannot*
subscribe to it. So there are two paths here and you should ship both:

1. **`WaveAtFriendsIntent`** (`BackTapIntent.swift`) — an App Intent the user
   assigns to Back Tap themselves. This is the only route that works with the
   phone locked or the app closed. It also lights up Siri, Shortcuts and the
   Action button for free. **Onboarding must explain the setup or nobody will
   find it.**
2. **`KnockDetector`** — an in-app accelerometer heuristic, active only while a
   screen asks for it. Works without user setup, but only in the foreground,
   and the threshold (`spikeThreshold = 2.2`) will need tuning on real hardware.
   Test it while walking before trusting it.

## First-build watchlist

Since this was written without a compiler, these are the spots most likely to
need a small fix — check them first if the build is red:

1. **`Map(position:selection:)`** in `MapScreen` uses tag-based selection. If
   the binding type doesn't line up, drop `selection:` and select purely from
   the pin's `onTapGesture` — the tap handler already sets `selected`.
2. **Supabase query decoding** — the nested `profiles!friend_id(*)` join in
   `FriendsService.load` depends on your actual foreign-key name. If it errors,
   run the select in the Supabase SQL editor first and copy the shape it returns.
3. **ActivityKit** APIs moved between iOS 16.1 and 16.2. This targets iOS 17,
   so `ActivityContent` (`.init(state:staleDate:)`) is correct — but if you drop
   the deployment target, that call changes.
4. **Package versions** in `project.yml` are `from:` minimums; SwiftPM will
   resolve newer majors' APIs differently if the packages have moved on.

## What is deliberately missing

Chat, groups, Highlights, Zenlands, footprints/heatmap, check-ins, friend
requests and invite redemption are **not** here. They are straightforward
ports of existing `src/services/*` logic and should be added screen by screen,
not in one pass.

Live Activities and the home-screen widget **are** implemented. What is still
open on that surface: a push-driven "friend arrived nearby" activity (needs an
ActivityKit push token registered with the backend), and interactive widget
buttons via App Intents.

## Architecture

```
Sources/
  App/            entry point, root routing, profile completion
  Auth/           AuthService (Apple + Google + Supabase), SignInView
  Config/         Info.plist properties live in project.yml; secrets here
  DesignSystem/   Theme.swift — the web app's tokens, ported
  Interactions/   BumpService, BumpActivityController, Haptics,
                  MotionGestures, BackTapIntent, ThrowView
  Map/            MapScreen, PersonCard, avatars and pins
  Model/          Profile, Friend, LiveLocation, GhostMode, Fix
  Services/       Supabase client, FriendsService, SocialService, LocationService
  Shared/         *** compiled into BOTH targets ***
                  BumpActivityAttributes, NearbySnapshot, ColorHex/Brand
Widgets/          Live Activity + home-screen widget (app-extension target)
Tests/            FixGateTests — the throttle logic, mirrored from the web
```

`Sources/Shared/` is the only code compiled into both the app and the widget
extension. Anything you put there must stay free of app-only dependencies, and
nothing defined there may be redefined in either target — that is why
`Color(hex:)` lives in `ColorHex.swift` and nowhere else.

**Ghost Mode masking stays server-side.** `FriendsService.load` reads the
`friend_locations` view, never the raw `locations` table, exactly like the web
client. Do not "optimise" that away.
