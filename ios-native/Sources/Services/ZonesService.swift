import Foundation
import Supabase

/// "Zenlands": friend-visible, hand-named places (unlike the private,
/// auto-detected significant places some apps infer from history). Port of
/// the web app's `services/zones.ts`.
struct Zone: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerId: UUID
    var label: String
    var emoji: String
    var lat: Double
    var lng: Double
    var radiusM: Int
    let createdAt: Date
}

enum ZonesService {
    static let emojiChoices = ["🏠", "🏢", "🏋️", "🎓", "☕️", "🍜", "🏥", "📍"]

    /// My own zones plus my friends' — RLS ("friends read zones") already
    /// limits the friend half to accepted-friendship rows sharing location
    /// with me, so nothing else needs filtering client side.
    static func loadVisible() async throws -> [Zone] {
        try await Backend.client
            .from("zones")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    static func create(ownerId: UUID, label: String, emoji: String, lat: Double, lng: Double, radiusM: Int = 120) async throws -> Zone {
        struct NewZone: Encodable {
            let ownerId: UUID
            let label: String
            let emoji: String
            let lat: Double
            let lng: Double
            let radiusM: Int
        }
        return try await Backend.client
            .from("zones")
            .insert(NewZone(ownerId: ownerId, label: label.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, lat: lat, lng: lng, radiusM: radiusM))
            .select()
            .single()
            .execute()
            .value
    }

    static func delete(_ id: UUID) async throws {
        try await Backend.client.from("zones").delete().eq("id", value: id).execute()
    }
}
