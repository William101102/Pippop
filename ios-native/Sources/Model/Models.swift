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

    var id: UUID { profile.id }
    var displayName: String { profile.displayName }

    /// Green ring = actually sharing right now. Mirrors the web rule: not
    /// frozen, and a fix within the last 30 minutes.
    var isLive: Bool {
        guard ghostMode != .frozen, let updated = location?.updatedAt else { return false }
        return Date().timeIntervalSince(updated) < 30 * 60
    }
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
