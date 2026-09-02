# Known Issues & Limitations — Pinpop iOS (native)

This file tracks the current state of `ios-native/` (the SwiftUI rewrite), honestly, including things that are incomplete, unverifiable, or deliberately simplified. Written after a session of getting real-device sign-in, the map, and the four dock tabs (Friends/Explore/Me/Messages) working.

## Not yet built

- **No incoming-friend-request UI.** `ExploreView` can *send* a request (writes a `friendships` row with `status: "pending"`). There is no screen where the recipient sees or accepts it — so right now a sent request just sits in the table forever. Needs an inbox screen plus an "accept" action that flips `status` to `"accepted"`.
- **Messages tab is a placeholder.** `MessagesView` is an honest "coming soon" empty state, not mocked-up fake data. It was never wired to a real backend because the messages table/schema was never confirmed (see "Could not verify" below).
- **Google's official "G" logo isn't in yet.** `SignInView` currently uses `Image(systemName: "g.circle.fill")` (an SF Symbol) as a stand-in for Google's real multicolor brand mark. Swap before shipping — Google's brand guidelines require their actual asset, not a system glyph.

## Could not verify against the web app this session

The native code in `Sources/` could be read and edited freely, but for this entire session `src/` (the web app's source), `schema.sql`, and `backend/supabase/migrations/*.sql` were locked — every read attempt returned a filesystem-level "resource busy" error, most likely because something on the Mac (a running dev server, or an editor) had them open. No live URL to the deployed web app was available either.

Practical effect: every native screen built this session (`FriendsView`, `ExploreView`, `MeView`, `MessagesView`, the four dock destinations) was built against the **already-confirmed native-side schema** (`Models.swift`, `FriendsService.swift`, `Supabase.swift`) rather than a side-by-side copy of the web app's actual UI and flows. They're functional and schema-safe, but pixel/behavior parity with the web app (the "一模一样" goal) has **not been verified** and may not be exact — text, spacing, copy, and edge-case behavior were judgment calls, not verified matches.

If you can free up `src/` (close whatever has it open, e.g. `npm run dev` or an editor) or send a live URL, the next session can actually diff native screens against the real web ones and close this gap for real.

## Deliberately conservative choices (not bugs)

- **Friend requests only ever write `status: "pending"`.** Never `"accepted"` — because `FriendsService.load` only returns `"accepted"` rows, a wrong guess about the real schema can't accidentally leak your location to someone who hasn't reciprocated. Worst case, a request just sits unread until an accept screen exists.
- **Google Sign-In "skip nonce checks."** The nonce-mismatch error you hit earlier is now fixed via Supabase's own documented setting for this exact situation (GoogleSignIn-iOS 7.1.0 has no API to pass a custom nonce — that only exists in an unstable pre-release SDK). This is Supabase's recommended configuration for this SDK version, not a shortcut.

## Apple Developer account limits (encoded in `project.yml`, not a code bug)

Signed with a **free/personal** Apple Developer team. Two capabilities are hard-blocked by Apple on free accounts and are commented out (not deleted) in `project.yml`'s entitlements:
- Sign In with Apple
- Push Notifications

Both have re-enable notes right next to them in `project.yml`. If/when this account upgrades to a paid Apple Developer Program membership, uncomment those two lines and re-run `xcodegen generate`.

Note: Apple's App Store Guideline 4.8 requires that an app offering Google Sign-In *also* offer Sign In with Apple before it can ship — `AuthService.swift` already implements it, it just can't be tested until the capability is enabled on a paid account.

## Hardware features that can't be tested solo

- **Bump (UWB "shake to meet")** needs two physical iPhones with UWB chips (iPhone 11+) in the same room to test either side of the interaction. Untested end-to-end this session — only the UI (including the now-added close button) was verified.

## Fixed this session (kept here for context, not action items)

- White-on-white unreadable text in every input field, app-wide — root cause was the app's fully hardcoded light-only color palette with no forced color scheme, so system Dark Mode silently flipped `TextField` text to white against the app's own hardcoded-white cards. Fixed with `.preferredColorScheme(.light)` at the app root, plus explicit `.foregroundStyle`/`.tint` on every `TextField`.
- Top toast overlapping the status bar, and all four bottom dock buttons being untappable — both traced to one root cause (`.ignoresSafeArea()` on a `ZStack` sibling in `MapScreen`) and fixed by switching to `.safeAreaInset`.
- `BumpView` had no way to back out of a non-matched state — added a persistent close button.
- `xcodegen generate` was silently wiping manually-set Xcode signing/capabilities on every regenerate — fixed by moving Team ID, xcconfig wiring, and entitlements into `project.yml` itself, so they're durable.
