import Foundation
import Supabase

enum MessagesService {
    /// Every 1:1 message between the two of you, oldest first. `group_id` is
    /// always null here — group threads go through a separate call once
    /// group chat lands.
    static func loadThread(meId: UUID, friendId: UUID) async throws -> [Message] {
        try await Backend.client
            .from("messages")
            .select()
            .or("and(sender_id.eq.\(meId),recipient_id.eq.\(friendId)),and(sender_id.eq.\(friendId),recipient_id.eq.\(meId))")
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Mirrors the server's own `messages_body_length` check (1–2000 chars)
    /// so a bad message fails fast client-side instead of round-tripping.
    static func send(from senderId: UUID, to recipientId: UUID, body: String, kind: MessageKind = .text) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MessageError.empty }
        guard text.count <= 2000 else { throw MessageError.tooLong }

        struct NewMessage: Encodable {
            let senderId: UUID
            let recipientId: UUID
            let body: String
            let kind: String
        }
        try await Backend.client
            .from("messages")
            .insert(NewMessage(senderId: senderId, recipientId: recipientId, body: text, kind: kind.rawValue))
            .execute()
    }

    static func sendWave(from senderId: UUID, to recipientId: UUID) async throws {
        try await send(from: senderId, to: recipientId, body: "👋", kind: .wave)
    }

    static func markThreadRead(meId: UUID, friendId: UUID) async throws {
        struct ReadUpdate: Encodable { let readAt: Date }
        try await Backend.client
            .from("messages")
            .update(ReadUpdate(readAt: .now))
            .eq("recipient_id", value: meId)
            .eq("sender_id", value: friendId)
            .is("read_at", value: nil)
            .execute()
    }

    /// Unread 1:1 message count keyed by whoever sent them — drives both the
    /// notifications feed and the bell badge.
    static func loadUnreadCounts(for meId: UUID) async throws -> [UUID: Int] {
        struct Row: Decodable { let senderId: UUID }
        let rows: [Row] = try await Backend.client
            .from("messages")
            .select("sender_id")
            .eq("recipient_id", value: meId)
            .is("read_at", value: nil)
            .execute()
            .value
        var counts: [UUID: Int] = [:]
        for row in rows { counts[row.senderId, default: 0] += 1 }
        return counts
    }

    /// One preview per friend — their most recent message with me, if any —
    /// for the conversation-list screen.
    static func loadLastMessage(meId: UUID, friendId: UUID) async throws -> Message? {
        let rows: [Message] = try await Backend.client
            .from("messages")
            .select()
            .or("and(sender_id.eq.\(meId),recipient_id.eq.\(friendId)),and(sender_id.eq.\(friendId),recipient_id.eq.\(meId))")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}

enum MessageError: LocalizedError {
    case empty
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty: "Message can't be empty"
        case .tooLong: "Message is too long — 2000 characters max"
        }
    }
}
