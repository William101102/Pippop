import Foundation
import Supabase

/// "Throw something at a friend", waves, and the notification-feed reads
/// that lean on the same `map_reactions` / `place_events` tables.
///
/// Split out of `FriendsService.swift` because this file was previously
/// writing `recipient_id` and `power` onto `map_reactions` — neither column
/// exists (the real schema uses `target_id`, and has no `power` column at
/// all; charge level is a purely client-side animation input). Those inserts
/// were failing silently against the real database. See
/// `backend/supabase/setup.sql`'s "Social layer" section for the schema this
/// now matches exactly.
enum SocialService {
    /// Sends a wave to every friend. Returns how many went out.
    @discardableResult
    static func waveAtEveryone() async throws -> Int {
        let session = try await Backend.client.auth.session
        let friends = try await FriendsService.load(for: session.user.id)
        guard !friends.isEmpty else { return 0 }

        struct Reaction: Encodable {
            let senderId: UUID
            let targetId: UUID
            let emoji: String
        }

        let payload = friends.map {
            Reaction(senderId: session.user.id, targetId: $0.id, emoji: "👋")
        }
        try await Backend.client.from("map_reactions").insert(payload).execute()
        return payload.count
    }

    static func throwEmoji(_ emoji: String, to friendId: UUID) async throws {
        let session = try await Backend.client.auth.session
        struct Reaction: Encodable {
            let senderId: UUID
            let targetId: UUID
            let emoji: String
        }
        try await Backend.client
            .from("map_reactions")
            .insert(Reaction(senderId: session.user.id, targetId: friendId, emoji: emoji))
            .execute()
    }

    /// Reactions aimed at me that haven't expired yet (`map_reactions` rows
    /// expire an hour after being sent) — feeds the notifications panel.
    static func loadMyReactions(for userId: UUID) async throws -> [MapReaction] {
        try await Backend.client
            .from("map_reactions")
            .select()
            .eq("target_id", value: userId)
            .gt("expires_at", value: Date.now)
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value
    }

    /// Friends' recent arrivals/departures for the notifications feed. RLS
    /// (`read friend place events`) already limits this to my own rows plus
    /// friends who still share their location with me.
    static func loadPlaceEvents(hours: Int = 12) async throws -> [PlaceEvent] {
        let since = Date.now.addingTimeInterval(-Double(hours) * 3600)
        return try await Backend.client
            .from("place_events")
            .select()
            .gte("created_at", value: since)
            .order("created_at", ascending: false)
            .limit(40)
            .execute()
            .value
    }

    /// Records a real-world meeting detected over UWB.
    ///
    /// This used to insert into a `bumps` table that — it turns out — no
    /// migration ever actually creates (checked against
    /// `backend/supabase/setup.sql` and every file in
    /// `backend/supabase/migrations/`: neither defines one). The call site
    /// in `BumpView` wraps this in `try?`, so every real-device Bump this
    /// session has been silently failing to persist anything — the match
    /// animation played, but no streak credit or record was ever written.
    ///
    /// Rather than add a new table + migration for a single-purpose "we met"
    /// marker, this reuses `map_reactions` (both sides insert their own 🤝
    /// row, same as any other throw) — the existing
    /// `touch_friend_streak_reaction` trigger already bumps the friendship
    /// streak on any reaction insert, so Bump gets streak credit for free,
    /// and the meeting shows up in the recipient's notifications feed like
    /// any other reaction.
    static func recordBump(with friendId: UUID) async throws {
        try await throwEmoji("🤝", to: friendId)
    }
}
