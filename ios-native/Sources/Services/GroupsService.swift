import Foundation
import Supabase

enum GroupsService {
    private struct GroupRow: Decodable {
        let id: UUID
        let name: String
        let ownerId: UUID
        let createdAt: Date
    }
    private struct MemberRow: Decodable {
        let groupId: UUID
        let userId: UUID
    }

    /// Groups I belong to, each with its member profiles attached — RLS on
    /// `chat_groups` (`is_group_member`) already limits this to groups I'm
    /// actually seated in.
    static func loadMyGroups() async throws -> [ChatGroup] {
        let rows: [GroupRow] = try await Backend.client
            .from("chat_groups")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }

        let memberRows: [MemberRow] = try await Backend.client
            .from("chat_group_members")
            .select("group_id, user_id")
            .in("group_id", values: rows.map(\.id))
            .execute()
            .value

        let memberIds = Array(Set(memberRows.map(\.userId)))
        let profiles: [Profile] = try await Backend.client
            .from("profiles")
            .select()
            .in("id", values: memberIds)
            .execute()
            .value
        let profileById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.map { group in
            let members = memberRows
                .filter { $0.groupId == group.id }
                .compactMap { profileById[$0.userId] }
            return ChatGroup(id: group.id, name: group.name, ownerId: group.ownerId, createdAt: group.createdAt, members: members)
        }
    }

    @discardableResult
    static func create(ownerId: UUID, name: String, memberIds: [UUID]) async throws -> ChatGroup {
        struct NewGroup: Encodable { let name: String; let ownerId: UUID }
        struct GroupRow: Decodable { let id: UUID; let name: String; let ownerId: UUID; let createdAt: Date }

        let group: GroupRow = try await Backend.client
            .from("chat_groups")
            .insert(NewGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), ownerId: ownerId))
            .select()
            .single()
            .execute()
            .value

        let allIds = Array(Set([ownerId] + memberIds))
        struct NewMember: Encodable { let groupId: UUID; let userId: UUID }
        try await Backend.client
            .from("chat_group_members")
            .insert(allIds.map { NewMember(groupId: group.id, userId: $0) })
            .execute()

        let profiles: [Profile] = try await Backend.client
            .from("profiles")
            .select()
            .in("id", values: allIds)
            .execute()
            .value

        return ChatGroup(id: group.id, name: group.name, ownerId: group.ownerId, createdAt: group.createdAt, members: profiles)
    }

    static func loadThread(groupId: UUID) async throws -> [Message] {
        try await Backend.client
            .from("messages")
            .select()
            .eq("group_id", value: groupId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Marks every unread group message addressed to a group I'm in as read
    /// — same `read_at` convention the 1:1 thread uses. RLS on `messages`
    /// limits the update to rows visible to me (i.e. my own groups).
    static func markThreadRead(meId: UUID, groupId: UUID) async throws {
        struct ReadUpdate: Encodable { let readAt: Date }
        try await Backend.client
            .from("messages")
            .update(ReadUpdate(readAt: .now))
            .eq("group_id", value: groupId)
            .neq("sender_id", value: meId)
            .is("read_at", value: nil)
            .execute()
    }

    /// Unread group-message count, summed across every group I'm a member of —
    /// feeds the bell badge so group activity isn't invisible there.
    static func loadGroupUnreadCount(for meId: UUID) async throws -> Int {
        struct Row: Decodable { let groupId: UUID }
        let rows: [Row] = try await Backend.client
            .from("messages")
            .select("group_id")
            .not("group_id", is: value: nil)
            .neq("sender_id", value: meId)
            .is("read_at", value: nil)
            .execute()
            .value
        return rows.count
    }

    static func send(senderId: UUID, groupId: UUID, body: String) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MessageError.empty }
        guard text.count <= 2000 else { throw MessageError.tooLong }
        struct NewMessage: Encodable {
            let senderId: UUID
            let groupId: UUID
            let body: String
            let kind: String
        }
        try await Backend.client
            .from("messages")
            .insert(NewMessage(senderId: senderId, groupId: groupId, body: text, kind: "text"))
            .execute()
    }
}
