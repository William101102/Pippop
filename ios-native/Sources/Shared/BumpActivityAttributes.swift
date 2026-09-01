import ActivityKit
import Foundation

/// Shared between the app and the widget extension — both targets compile this
/// file (see `project.yml`), so the types must stay free of app-only imports.
struct BumpActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the activity.
    let friendName: String

    /// Updated as the two phones close in.
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case searching, tracking, met
        }

        var phase: Phase
        /// Metres. Nil while UWB is still resolving a first measurement.
        var distance: Double?
        /// Radians, 0 = straight ahead. Nil when direction can't be resolved
        /// (phone orientation, or no line of sight).
        var bearing: Double?

        var headline: String {
            switch phase {
            case .searching: "Looking for them…"
            case .tracking: distanceText
            case .met: "You met!"
            }
        }

        var distanceText: String {
            guard let distance else { return "Getting a fix…" }
            return distance < 1
                ? String(format: "%.0f cm", distance * 100)
                : String(format: "%.1f m", distance)
        }

        /// 0–1, used to fill the progress ring. Six metres reads as "far".
        var proximity: Double {
            guard let distance else { return 0 }
            return max(0, min(1, 1 - distance / 6))
        }
    }
}
