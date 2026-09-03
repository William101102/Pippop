import Foundation
import Supabase

enum FriendsService {
    /// `friendships` has no `friend_id`/`user_id` column — it stores a
    /// symmetric pair (`requester_id`, `addressee_id`); either side can be
    /// "me" depending on who sent the request. See
    /// `backend/supabase/setup.sql`, which this file is a direct port of.
    private struct FriendshipRow: Decodable {
        let id: UUID
        let requesterId: UUID
        let addresseeId: UUID
        let streakDays: Int?
        let lastInteractionOn: Date?
        let streakGraceValue: Int?
        let streakGraceDays: Int?
    }

    /// Loads friends plus their **masked** positions.
    ///
    /// Reads `friend_locations`, never `locations`. That view is where Ghost
    /// Mode's blur and freeze are applied in SQL — querying the raw table
    /// would hand the client true coordinates the owner chose to hide.
    static func load(for userId: UUID) async throws -> [Friend] {
        let rows: [FriendshipRow] = try await Backend.client
            .from("friendships")
            .select("id, requester_id, addressee_id, streak_days, last_interaction_on, streak_grace_value, streak_grace_days")
            .or("requester_id.eq.\(userId),addressee_id.eq.\(userId)")
            .eq("status", value: "accepted")
            .execute()
            .value

        guard !rows.isEmpty else { return [] }

        let friendIds = rows.map { $0.requesterId == userId ? $0.addresseeId : $0.requesterId }

        async let profilesTask: [Profile] = Backend.client
            .from("profiles")
            .select()
            .in("id", values: friendIds)
            .execute()
            .value

        async let locationsTask: [LiveLocation] = Backend.client
            .from("friend_locations")
            .select()
            .in("user_id", values: friendIds)
            .execute()
            .value

        async let bestFriendTask: Set<UUID> = loadBestFriendIds(for: userId)

        let (profiles, locations, bestFriendIds) = try await (profilesTask, locationsTask, bestFriendTask)

        let locationById = Dictionary(uniqueKeysWithValues: locations.map { ($0.userId, $0) })
        let rowByFriendId = Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (row.requesterId == userId ? row.addresseeId : row.requesterId, row)
            }
        )

        return profiles.map { profile in
            let row = rowByFriendId[profile.id]
            return Friend(
                profile: profile,
                location: locationById[profile.id],
                isBestFriend: bestFriendIds.contains(profile.id),
                streakDays: row?.streakDays ?? 0,
                lastInteractionOn: row?.lastInteractionOn,
                streakGraceValue: row?.streakGraceValue,
                streakGraceDays: row?.streakGraceDays ?? 0
            )
        }
    }

    /// Pending requests addressed to me, with the requester's profile
    /// attached — what the "friend requests" inbox shows.
    static func loadRequests(for userId: UUID) async throws -> [FriendRequest] {
        struct Row: Decodable {
            let id: UUID
            let requesterId: UUID
        }
        let rows: [Row] = try await Backend.client
            .from("friendships")
            .select("id, requester_id")
            .eq("addressee_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        let profiles: [Profile] = try await Backend.client
            .from("profiles")
            .select()
            .in("id", values: rows.map(\.requesterId))
            .execute()
            .value
        let profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.compactMap { row in
            guard let profile = profileById[row.requesterId] else { return nil }
            return FriendRequest(relId: row.id, profile: profile)
        }
    }

    /// Accept or decline an incoming request. Only the addressee may
    /// actually flip the status — enforced server-side by the "respond to
    /// friend request" RLS policy — so this simply attempts the update and
    /// lets a rejected write surface as a thrown error.
    static func respond(_ relId: UUID, accept: Bool) async throws {
        struct StatusUpdate: Encodable { let status: String }
        try await Backend.client
            .from("friendships")
            .update(StatusUpdate(status: accept ? "accepted" : "declined"))
            .eq("id", value: relId)
            .execute()
    }

    /// Sends a request, or — if the target already invited *us* first —
    /// accepts theirs instead, so two people adding each other pairs up
    /// rather than creating a second row for the same relationship (blocked
    /// anyway by the `unique(requester_id, addressee_id)` constraint... which
    /// only covers one direction, hence checking both explicitly here).
    @discardableResult
    static func sendRequest(from meId: UUID, to targetId: UUID) async throws -> String {
        struct ExistingRow: Decodable {
            let id: UUID
            let requesterId: UUID
            let addresseeId: UUID
            let status: String
        }
        let existing: [ExistingRow] = try await Backend.client
            .from("friendships")
            .select("id, requester_id, addressee_id, status")
            .or("and(requester_id.eq.\(meId),addressee_id.eq.\(targetId)),and(requester_id.eq.\(targetId),addressee_id.eq.\(meId))")
            .execute()
            .value

        if let row = existing.first {
            if row.status == "accepted" { return "already_friends" }
            if row.addresseeId == meId {
                try await respond(row.id, accept: true)
                return "accepted"
            }
            if row.status == "pending" { return "already_sent" }
            struct StatusUpdate: Encodable { let status: String }
            try await Backend.client
                .from("friendships")
                .update(StatusUpdate(status: "pending"))
                .eq("id", value: row.id)
                .execute()
            return "sent"
        }

        struct NewFriendship: Encodable {
            let requesterId: UUID
            let addresseeId: UUID
            let status: String
        }
        try await Backend.client
            .from("friendships")
            .insert(NewFriendship(requesterId: meId, addresseeId: targetId, status: "pending"))
            .execute()
        return "sent"
    }

    static func loadBestFriendIds(for ownerId: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let friendId: UUID }
        let rows: [Row] = try await Backend.client
            .from("best_friends")
            .select("friend_id")
            .eq("owner_id", value: ownerId)
            .execute()
            .value
        return Set(rows.map(\.friendId))
    }

    static func setBestFriend(_ friendId: UUID, ownerId: UUID, pinned: Bool) async throws {
        if pinned {
            struct Row: Encodable { let ownerId: UUID; let friendId: UUID }
            try await Backend.client
                .from("best_friends")
                .upsert(Row(ownerId: ownerId, friendId: friendId), onConflict: "owner_id,friend_id")
                .execute()
        } else {
            try await Backend.client
                .from("best_friends")
                .delete()
                .eq("owner_id", value: ownerId)
                .eq("friend_id", value: friendId)
                .execute()
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
