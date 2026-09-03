import Foundation
import CoreLocation

/// Mirrors the `profiles` table. Column names are snake_case in Postgres; the
/// Supabase decoder is configured for `.convertFromSnakeCase` in SupabaseClient.
struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarUrl: String?
    var avatarColor: String?
    var statusEmoji: String?
    var statusText: String?
    var batteryLevel: Int?
    var isCharging: Bool?
    var lastActiveAt: Date?
}

/// Three privacy levels, matching `location_privacy.mode` on the server.
///
/// Blur and freeze are applied **server-side** by the `friend_locations` view —
/// the client never receives a friend's true coordinate when they have hidden
/// it. Do not reimplement masking here.
enum GhostMode: String, Codable, CaseIterable, Sendable {
    case precise, blurred, frozen

    var title: String {
        switch self {
        case .precise: "Precise"
        case .blurred: "Blurred"
        case .frozen: "Frozen"
        }
    }

    var detail: String {
        switch self {
        case .precise: "Friends see exactly where you are."
        case .blurred: "Friends see a neighbourhood, offset 0.2–1.2 km."
        case .frozen: "Friends stay pinned to your last shared spot."
        }
    }

    var symbol: String {
        switch self {
        case .precise: "location.fill"
        case .blurred: "circle.dashed"
        case .frozen: "snowflake"
        }
    }
}

struct LiveLocation: Codable, Hashable, Sendable {
    let userId: UUID
    var lat: Double
    var lng: Double
    var accuracy: Double?
    var speed: Double?
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

extension LiveLocation: Identifiable {
    var id: UUID { userId }
}

struct Friend: Identifiable, Hashable, Sendable {
    let profile: Profile
    var location: LiveLocation?
    var ghostMode: GhostMode = .precise
    var isBestFriend: Bool = false
    var streakDays: Int = 0
    var lastInteractionOn: Date?
    /// Set together server-side once a missed-day repair window opens — see
    /// `StreakInfo`/`bump_friend_streak` in `setup.sql`.
    var streakGraceValue: Int?
    var streakGraceDays: Int = 0

    var id: UUID { profile.id }
    var displayName: String { profile.displayName }

    /// Green ring = actually sharing right now. Mirrors the web rule: not
    /// frozen, and a fix within the last 30 minutes.
    var isLive: Bool {
        guard ghostMode != .frozen, let updated = location?.updatedAt else { return false }
        return Date().timeIntervalSince(updated) < 30 * 60
    }

    /// Same tiered streak read the web app shows — spark/flame/blaze/legend,
    /// at-risk, or mid-repair. See `StreakInfo`.
    var streak: StreakInfo {
        StreakInfo.compute(
            streakDays: streakDays,
            lastInteractionOn: lastInteractionOn,
            graceValue: streakGraceValue,
            graceDays: streakGraceDays
        )
    }
}

/// A pending incoming friend request — the requester's own profile, plus the
/// `friendships` row id needed to accept/decline it.
struct FriendRequest: Identifiable, Hashable, Sendable {
    let relId: UUID
    let profile: Profile
    var id: UUID { relId }
}

/// Mirrors `messages.kind` — same catalog as the web app's `MessageKind`.
enum MessageKind: String, Codable, Sendable {
    case text, emoji, wave, image, location
    case whatsUp = "whats_up"
}

/// A 1:1 or group message. Exactly one of `recipientId`/`groupId` is set,
/// matching the `messages_recipient_or_group` check constraint.
struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let senderId: UUID
    var recipientId: UUID?
    var groupId: UUID?
    var body: String
    let createdAt: Date
    var kind: MessageKind?
    var readAt: Date?
}

/// A group chat, with its member profiles already attached.
struct ChatGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let ownerId: UUID
    let createdAt: Date
    var members: [Profile]
}

/// An emoji dropped on a friend's pin — a throw, a wave, or a Bump 🤝. Rows
/// expire an hour after being sent (`map_reactions.expires_at`).
struct MapReaction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let senderId: UUID
    let targetId: UUID
    let emoji: String
    let createdAt: Date
}

enum PlaceEventKind: String, Codable, Sendable {
    case arrive, leave
}

/// "Alex arrived at Office" — written by the mover's own device for the
/// notifications feed.
struct PlaceEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let kind: PlaceEventKind
    let label: String
    var lat: Double?
    var lng: Double?
    let createdAt: Date
}

/// A fix from CoreLocation, normalised before it reaches the upload gate.
struct Fix: Sendable, Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double?
    let speed: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    init(_ location: CLLocation) {
        lat = location.coordinate.latitude
        lng = location.coordinate.longitude
        accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        speed = location.speed >= 0 ? location.speed : nil
    }
}

extension Date {
    /// Short relative label ("3m ago", "yesterday") for chat and
    /// notification rows — the Swift equivalent of the web app's `timeAgo`.
    var relativeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
