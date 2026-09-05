import ActivityKit
import Foundation

/// "Heading to Maya" — the Live Activity that runs from the moment you set
/// off to meet someone until you actually reach them.
///
/// Compiled into both the app and the widget extension (see `project.yml`),
/// so it must stay free of app-only imports.
///
/// ## Why there's no avatar photo in here
///
/// A `ContentState` has a hard **4 KB** budget, and a widget extension can't
/// fetch a remote image while rendering. So the island shows the same
/// fallback the app does when a photo hasn't loaded: the initial on the
/// person's own avatar colour. Cheap, always available, and recognisably
/// theirs.
struct MeetupActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the activity.
    let friendName: String
    /// First letter, precomputed — the extension shouldn't be doing string
    /// munging on a name it can't validate.
    let friendInitial: String
    /// `profiles.avatar_color`, as a hex string. Nil falls back to coral,
    /// exactly like `AvatarView`.
    let avatarColorHex: String?
    /// Metres between you when the trip started. The progress ring is "how
    /// much of *this* have you closed", so it needs the starting point.
    let startDistance: Double
    /// Deep link back into the app — `pinpop://friend/<uuid>`.
    let friendURL: URL?

    struct ContentState: Codable, Hashable {
        /// Metres. Nil when the friend's location hasn't come through yet.
        var distance: Double?
        /// Degrees clockwise from north, for the arrow. Nil when either side
        /// has no fix to bear from.
        var bearing: Double?
        /// Their status emoji, so the island carries a bit of them and not
        /// just a number.
        var statusEmoji: String?
        /// Their fix has gone quiet (>30 min) — the island stops claiming a
        /// live distance and says when they were last seen instead.
        var isStale: Bool = false
        /// When their position was last known. Rendered with a relative
        /// style, so it keeps counting up without us pushing updates.
        var lastSeen: Date = .now
        /// Set once you're basically on top of each other. The activity ends
        /// shortly after, but this is the beat that makes it feel like an
        /// arrival rather than a disappearance.
        var hasArrived: Bool = false

        /// 0–1 for the progress ring. Guards a zero/absent start distance,
        /// which would otherwise divide by zero on a trip that began with
        /// the two of you already together.
        func progress(from start: Double) -> Double {
            guard start > 0, let distance else { return 0 }
            return max(0, min(1, 1 - distance / start))
        }

        /// Big number and small unit, split for the island's stacked layout.
        /// Metres under a kilometre, one decimal above — matching `Fmt`
        /// in the app so the two never disagree.
        var distanceParts: (value: String, unit: String) {
            guard let distance else { return ("—", "") }
            return distance < 1000
                ? (String(format: "%.0f", distance), "m")
                : (String(format: "%.1f", distance / 1000), "km")
        }

        var compactText: String {
            if hasArrived { return "Here" }
            guard !isStale else { return "—" }
            let parts = distanceParts
            return parts.unit.isEmpty ? parts.value : parts.value + parts.unit
        }

        var headline: String {
            if hasArrived { return "You're together" }
            if isStale { return "Waiting for their location" }
            return "On your way"
        }
    }
}
