import Foundation
import Supabase

enum FriendsService {
    /// Loads friends plus their **masked** positions.
    ///
    /// Reads `friend_locations`, never `locations`. That view is where Ghost
    /// Mode's blur and freeze are applied in SQL — querying the raw table would
    /// hand the client true coordinates the owner chose to hide, and RLS is
    /// written on the assumption that nobody does that.
    static func load(for userId: UUID) async throws -> [Friend] {
        struct FriendRow: Decodable {
            let friendId: UUID
            let isBestFriend: Bool?
            let streakDays: Int?
            let lastInteractionOn: Date?
            let profile: Profile
        }

        let rows: [FriendRow] = try await Backend.client
            .from("friendships")
            .select("friend_id, is_best_friend, streak_days, last_interaction_on, profile:profiles!friend_id(*)")
            .eq("user_id", value: userId)
            .eq("status", value: "accepted")
            .execute()
            .value

        guard !rows.isEmpty else { return [] }

        let locations: [LiveLocation] = try await Backend.client
            .from("friend_locations")
            .select()
            .in("user_id", values: rows.map(\.friendId))
            .execute()
            .value

        let byId = Dictionary(uniqueKeysWithValues: locations.map { ($0.userId, $0) })

        return rows.map { row in
            Friend(
                profile: row.profile,
                location: byId[row.friendId],
                isBestFriend: row.isBestFriend ?? false,
                streakDays: row.streakDays ?? 0,
                lastInteractionOn: row.lastInteractionOn
            )
        }
    }

    static func setGhostMode(_ mode: GhostMode, ownerId: UUID, frozen: Fix?) async throws {
        struct Row: Encodable {
            let ownerId: UUID
            let viewerId: UUID
            let mode: String
            let frozenLat: Double?
            let frozenLng: Double?
            let updatedAt: Date
        }
        let row = Row(
            ownerId: ownerId,
            viewerId: ownerId, // the self row is owner == viewer
            mode: mode.rawValue,
            frozenLat: mode == .frozen ? frozen?.lat : nil,
            frozenLng: mode == .frozen ? frozen?.lng : nil,
            updatedAt: .now
        )
        try await Backend.client
            .from("location_privacy")
            .upsert(row, onConflict: "owner_id,viewer_id")
            .execute()
    }
}

enum SocialService {
    /// Sends a wave to every friend. Returns how many went out.
    @discardableResult
    static func waveAtEveryone() async throws -> Int {
        let session = try await Backend.client.auth.session
        let friends = try await FriendsService.load(for: session.user.id)
        guard !friends.isEmpty else { return 0 }

        struct Reaction: Encodable {
            let senderId: UUID
            let recipientId: UUID
            let emoji: String
        }

        let payload = friends.map {
            Reaction(senderId: session.user.id, recipientId: $0.id, emoji: "👋")
        }
        try await Backend.client.from("map_reactions").insert(payload).execute()
        return payload.count
    }

    static func throwEmoji(_ emoji: String, to friendId: UUID, power: Double) async throws {
        let session = try await Backend.client.auth.session
        struct Reaction: Encodable {
            let senderId: UUID
            let recipientId: UUID
            let emoji: String
            /// 0–1; the receiving client scales its celebration to match.
            let power: Double
        }
        try await Backend.client
            .from("map_reactions")
            .insert(Reaction(
                senderId: session.user.id, recipientId: friendId,
                emoji: emoji, power: min(max(power, 0), 1)
            ))
            .execute()
    }

    /// Records a real-world meeting detected over UWB. Both sides insert their
    /// own row; the server pairs them and bumps the streak.
    static func recordBump(with friendId: UUID) async throws {
        let session = try await Backend.client.auth.session
        struct Bump: Encodable {
            let userId: UUID
            let friendId: UUID
            let happenedAt: Date
        }
        try await Backend.client
            .from("bumps")
            .insert(Bump(userId: session.user.id, friendId: friendId, happenedAt: .now))
            .execute()
    }
}
