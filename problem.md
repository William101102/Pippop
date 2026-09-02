# Known Issues & Limitations — Pinpop iOS (native)

This file tracks the current, honest state of `ios-native/` (the SwiftUI rewrite) — what's built, what's simplified on purpose, and what's still missing. Last rewritten after a session that ported nearly all of the web app's remaining feature set onto native (friend requests, chat, groups, Highlights/stories, check-ins, Zenlands, footprints, notifications) and fixed several schema bugs that had been silently broken since earlier in the project.

## What shipped this pass

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

Everything above was built by reading the real DB schema (`backend/supabase/setup.sql`) and the real, pinned Supabase Swift SDK source (cloned locally at the exact resolved revision, `2.55.1`, to confirm method signatures) rather than by guessing — but none of it has gone through an actual Xcode build, since there's no way to compile Swift from this side. **William should build in Xcode before trusting any of this compiles and runs.** If `xcodegen generate` hasn't been re-run since these files landed, run it first — several are in new folders (`Sources/Highlights/`, and new files under `Sources/Messages/`), though `project.yml`'s `sources: - path: Sources` globs recursively so no `project.yml` edit should be needed.

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
