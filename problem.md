# Known Issues & Limitations — Pinpop iOS (native)

This file tracks the current, honest state of `ios-native/` (the SwiftUI rewrite) — what's built, what's simplified on purpose, and what's still missing.

## Design-fidelity pass (matching the web app's exact look)

William asked for the native UI to match the web app's actual visual design ("完完全全" — completely, not just close), not only its features. This pass read all 1081 lines of `src/styles.css` (the web app's full design system — CSS custom properties, every component class) and ported the parts that are shared, reusable primitives, since those cascade correctly to every screen automatically:

- **Real fonts, not a system-font stand-in.** The web app loads `Fredoka` (headlines) and `DM Sans` (body) from Google Fonts. Neither ships pre-built static weights, so the two variable fonts were downloaded from Google's own font repo and sliced into fixed-weight `.ttf`s with `fonttools varLib.instancer` (Medium/SemiBold/Bold for Fredoka, Medium/SemiBold/Bold/ExtraBold for DM Sans — the same weights the CSS `@import` requests), bundled under `Sources/Resources/Fonts/` with their OFL license text, and registered via `UIAppFonts` in `project.yml`. `Theme.Font.display`/`.body` now resolve to the real families everywhere they're already called — no per-screen changes needed for this to take effect.
- **Avatars are a rounded square ("squircle"), not a circle.** `.avatar-photo`/`.avatar` in the web app use `border-radius: 16px` on a 46px box (ratio ≈ .348, which holds close enough across every size the web app uses — 70px→25, 86px→30 — to use as one formula instead of a lookup table). `AvatarView` was rewritten with this shape by default, with an explicit `.circle` override for the two places the web app itself switches shapes: map pins and the Highlights story ring.
- **Map pins**: circular (not squircle), 5px white border, with the web app's pulsing green ring (`@keyframes pulse-ring`) while a friend is actually live, a static grey ring when hidden/stale, plus grayscale+opacity for away friends — `FriendPin` was rewritten to match `.person-pin`/`.person-pin.live::after` exactly.
- **Exact shadow/color tokens.** Added the CSS custom properties that weren't ported the first time (`--fill`, `--violet-soft`, `--danger-*`, `--warn-*`, `--info-*`, the dock's own resting-icon grey `#7a7189` which the web app deliberately never routes through `--muted`), and split the one generic card shadow into the three distinct `box-shadow` recipes the web app actually uses (topbar circle buttons vs. the dock vs. sheets) rather than reusing one value everywhere.
- **Real glass/blur chrome.** The topbar's profile pill, notification bell and Bump button, plus the dock, use `backdrop-filter: blur()` over translucent white in CSS (`--glass`/`--glass-solid`). `FloatingCard` gained a `style` (glass / glassSolid / dock / card) that renders those with an actual SwiftUI Material instead of a flat white card.
- **Dock**: the resting tab color now matches the web app's own grey instead of reusing `--muted`, and the active tab gets the web app's violet pill background (`.dock button.active`) instead of no indication at all.
- **Chat bubbles**: the "tail" corner (bottom-right for mine, bottom-left for theirs) is now flattened to 6px like `.chat-bubble`, instead of a uniform rounded rect, in both 1:1 and group chat.
- **Full streak-badge system.** `PersonCard` only ever showed a static "🔥 N-day streak" pill. Ported `src/lib/streak.ts`'s tier/at-risk/repair-grace math as `StreakInfo.swift` (added `streak_grace_value`/`streak_grace_days` to the `friendships` query), so the badge now shows the same spark/flame/blaze/legend tiers, the pulsing at-risk and can-repair warnings, and the repairing state, with the same color recipes as `.streak-badge.*`.
- **Distance card → compass card.** `PersonCard`'s plain "150 m · Live" pill was replaced with a small heading dial (bearing computed from both coordinates, same great-circle formula as the web app's `bearingDeg`) plus a compass-point label, matching `.person-compass`/`.compass-ring`.

None of this has been seen rendered — see "Not yet verified" below; the fonts in particular (`Font.custom` silently falls back to the system font if a bundled name is misspelled or `UIAppFonts` is missing an entry) should be the first thing William checks after rebuilding.

### Deliberately not attempted this pass (real CSS features, not yet ported)

Read in full but judged too large or too separate from "shared primitive" work to fold into this pass safely without being able to see a render:
- **Story map pins** (`.story-pin`/`.story-ring`) — Highlights with a location currently only show in the horizontal rail, not as their own animated-gradient-ring pin on the map itself, the way the web app places them.
- **Gift-toast** (the celebratory popup for an *incoming* throw/reaction) and the **invite-welcome card** (redeeming an invite token) — both exist in CSS, neither has a native screen yet.
- **Per-message avatar in group chat bubbles** (`.chat-bubble-row`/`.chat-bubble-avatar`) — `GroupChatView` shows the sender's name above a run of messages but not a small avatar beside each one.
- Several rows/lists (conversation list, zone list, footprint list) render as solid floating cards in native; the web app's equivalents are flatter, transparent list rows (`.friend-row{background:transparent}`). This predates this pass and wasn't restructured — it's a legitimate style choice, just not a literal match.
- Per-component shadow/radius values for the many smaller CSS classes not covered above (`.chip`, `.stat-card`, `.feature-grid` tiles, etc.) still use this file's original approximations rather than a line-by-line port.

## What shipped in the feature-parity pass

Built in three phases, each committed to the device as it finished:

- **Social core** — incoming/outgoing friend request inbox (`FriendsView`), an in-app notifications bell (requests, unread messages, reactions, friend arrive/leave activity), and real 1:1 chat (`MessagesView` → `ChatView`) backed by the `messages` table.
- **Location features** — check-in flow (`CheckInView`, reverse-geocoded via Nominatim), a merged Explore screen with nearby friends + nearby places (mirrors web's `NearbyPanel`), Zenlands/zones create-and-list, and a footprints summary (top 5 frequent places via the `my_frequent_places` RPC) — both folded into `MeView`'s new "My World" section.
- **Highlights & groups** — 24-hour-expiring photo/text stories with a horizontally-scrolling rail on the map screen and a full-screen viewer, plus group chat (create a group, group thread, `MessagesView` now lists both DMs and groups) and a streak-milestone celebration in `PersonCard` (mirrors web's `STREAK_MILESTONES`, using `UserDefaults` in place of `localStorage`).

This closes essentially every gap that existed between the web app and the native app at the start of this pass. Nothing here was verified by an actual Xcode build — see "Not yet verified" below.

## Real bugs found and fixed this pass

`src/` and `backend/supabase/setup.sql` had been locked (unreadable) for the entire prior session, so earlier native code was written against a **guessed** schema. Once they became readable, comparing native code against the real schema turned up bugs that had been shipping silently:

- **`FriendsService` was querying columns that don't exist.** The `friendships` table actually has `requester_id`/`addressee_id` (a symmetric request pair), not `friend_id`/`user_id`/`is_best_friend`. Best-friend status is its own table, `best_friends` (`owner_id`, `friend_id`). Rewrote `FriendsService` to match.
- **`SocialService.throwEmoji` was inserting a `power` column into `map_reactions` that doesn't exist**, and reading `recipient_id` instead of the real column, `target_id`. Fixed.
- **`SocialService.recordBump` was inserting into a `bumps` table that doesn't exist anywhere in the schema.** Because the call site wrapped it in `try?`, this had been failing silently all along — a successful real-device Bump was never actually recorded, so no streak credit was ever given for it. Fixed by repurposing `map_reactions` (a 🤝 emoji insert), which also gets streak credit for free via the existing `touch_friend_streak_reaction` trigger.
- **`ExploreView.sendRequest` had its own separate, independently-broken friendship insert** (using `userId`/`friendId` columns) that duplicated — badly — what `FriendsService` should have owned. Now delegates to `FriendsService.sendRequest`.

None of these four were reported by William — they were caught by re-reading the real schema and diffing it against what the native code assumed.

## Deliberate simplifications (not bugs)

- **Chat has no live push — it polls.** Both 1:1 (`ChatView`) and group (`GroupChatView`) threads re-fetch every 4 seconds while the screen is open, instead of subscribing to `supabase_realtime` on `messages`. Simple, and good enough for a chat that's mostly used synchronously, but a message won't appear until the next poll tick, and the app doesn't notify you of a new message while you're not looking at the thread.
- **Footprints has no heatmap.** Only the *list* of frequent places (`my_frequent_places` RPC) is shown, in `MeView`'s "My World" section. The web app's actual heatmap overlay would need a custom `MKOverlay`/`MKOverlayRenderer` on the map — bigger, separate work, not started.
- **The notification bell doesn't count unread group messages**, only pending friend requests and unread 1:1 messages — group unread-counting wasn't wired into `refreshNotificationCount`.
- **Highlights are photo-or-text, not video.** A story is either one photo (resized client-side to 960px, JPEG) with an optional caption, or a text-only card if no photo is attached — matches the web app's own scope.
- **Group creation requires at least 2 other people** (3 total) — picked so "group chat" doesn't overlap with an ordinary 1:1 conversation; there's no technical reason it couldn't be lower if that's not the right call.
- **Google's official "G" logo isn't in yet.** `SignInView` still uses `Image(systemName: "g.circle.fill")` as a stand-in — swap before shipping, since Google's brand guidelines require their real asset.

## Not yet verified

Everything above was built by reading the real DB schema (`backend/supabase/setup.sql`), the real, pinned Supabase Swift SDK source (cloned locally at the exact resolved revision, `2.55.1`, to confirm method signatures), and — for the design-fidelity pass — the real `src/styles.css` values, rather than by guessing. None of it has gone through an actual Xcode build or been seen rendered, since there's no way to compile Swift or preview SwiftUI from this side. **William should build in Xcode before trusting any of this compiles and runs.** Re-run `xcodegen generate` first — this pass added a new `Sources/Resources/Fonts/` folder and changed `project.yml` itself (the new `UIAppFonts` entries), which `xcodegen generate` needs to pick up even though plain new `.swift` files elsewhere would have been auto-globbed already. Specific things worth checking first:
- The Fredoka/DM Sans headlines actually render in the bundled font, not the system font (`Font.custom` fails silently to a system fallback if a name is misspelled or `UIAppFonts` is missing an entry — there'd be no build error, just the wrong-looking font).
- Avatars render as rounded squares everywhere except map pins and story rings, which should stay circular.
- `UnevenRoundedRectangle`'s `.rect(topLeadingRadius:...)` static factory (used for the chat-bubble tail corner) — iOS 17 API, matches the deployment target, but wasn't seen compile.

## Apple Developer account limits (encoded in `project.yml`, not a code bug)

Signed with a **free/personal** Apple Developer team. Two capabilities are hard-blocked by Apple on free accounts and are commented out (not deleted) in `project.yml`'s entitlements:
- Sign In with Apple
- Push Notifications

Both have re-enable notes right next to them in `project.yml`. If/when this account upgrades to a paid Apple Developer Program membership, uncomment those two lines and re-run `xcodegen generate`.

Note: Apple's App Store Guideline 4.8 requires that an app offering Google Sign-In *also* offer Sign In with Apple before it can ship — `AuthService.swift` already implements it, it just can't be tested until the capability is enabled on a paid account.

## Hardware features that can't be tested solo

- **Bump (UWB "shake to meet")** needs two physical iPhones with UWB chips (iPhone 11+) in the same room to test either side of the interaction. The persistence bug above (nonexistent `bumps` table) is now fixed, but the interaction still hasn't been tested end-to-end on real hardware.

## Fixed in earlier sessions (kept here for context, not action items)

- White-on-white unreadable text in every input field, app-wide — root cause was the app's fully hardcoded light-only color palette with no forced color scheme, so system Dark Mode silently flipped `TextField` text to white against the app's own hardcoded-white cards. Fixed with `.preferredColorScheme(.light)` at the app root, plus explicit `.foregroundStyle`/`.tint` on every `TextField`.
- Top toast overlapping the status bar, and all four bottom dock buttons being untappable — both traced to one root cause (`.ignoresSafeArea()` on a `ZStack` sibling in `MapScreen`) and fixed by switching to `.safeAreaInset`.
- `BumpView` had no way to back out of a non-matched state — added a persistent close button.
- `xcodegen generate` was silently wiping manually-set Xcode signing/capabilities on every regenerate — fixed by moving Team ID, xcconfig wiring, and entitlements into `project.yml` itself, so they're durable.
