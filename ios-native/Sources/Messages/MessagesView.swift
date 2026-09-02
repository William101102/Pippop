import SwiftUI

private struct Conversation: Identifiable {
    let friend: Friend
    var lastMessage: Message?
    var unreadCount: Int
    var id: UUID { friend.id }
}

/// The Messages tab — a real conversation list backed by the `messages`
/// table, replacing the earlier "coming soon" placeholder now that `src/`
/// (and its `messages`-table schema in `backend/supabase/setup.sql`) can
/// actually be read. Also lists group chats (`chat_groups`), with a "New
/// Group" entry point — port of the web app's conversation list plus
/// `NewGroupSheet`.
struct MessagesView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [Friend] = []
    @State private var conversations: [Conversation] = []
    @State private var groups: [ChatGroup] = []
    @State private var loading = true
    @State private var showNewGroup = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if loading {
                    ProgressView().tint(Theme.violet)
                } else if conversations.isEmpty && groups.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if !groups.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("GROUPS")
                                        .font(Theme.Font.body(10, weight: .heavy))
                                        .kerning(1.2)
                                        .foregroundStyle(Theme.muted)
                                        .padding(.horizontal, 4)
                                    ForEach(groups) { group in
                                        NavigationLink {
                                            GroupChatView(group: group)
                                        } label: {
                                            GroupRow(group: group)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !conversations.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    if !groups.isEmpty {
                                        Text("DIRECT MESSAGES")
                                            .font(Theme.Font.body(10, weight: .heavy))
                                            .kerning(1.2)
                                            .foregroundStyle(Theme.muted)
                                            .padding(.horizontal, 4)
                                    }
                                    ForEach(conversations) { conversation in
                                        NavigationLink {
                                            ChatView(friend: conversation.friend)
                                        } label: {
                                            ConversationRow(conversation: conversation)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNewGroup = true
                    } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .disabled(friends.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
            .sheet(isPresented: $showNewGroup) {
                NewGroupView(friends: friends) { group in
                    groups.insert(group, at: 0)
                }
            }
        }
        .task { await reload() }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("💬").font(.system(size: 44))
            Text("No conversations yet")
                .font(Theme.Font.body(15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Add a friend, then say hi from their card.")
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func reload() async {
        guard let meId = auth.profile?.id else { return }
        loading = conversations.isEmpty && groups.isEmpty

        async let friendsLoad = (try? FriendsService.load(for: meId)) ?? []
        async let unreadLoad = (try? MessagesService.loadUnreadCounts(for: meId)) ?? [:]
        async let groupsLoad = (try? GroupsService.loadMyGroups()) ?? []

        let (loadedFriends, unread, loadedGroups) = await (friendsLoad, unreadLoad, groupsLoad)
        friends = loadedFriends
        groups = loadedGroups.sorted { $0.createdAt > $1.createdAt }

        var loaded: [Conversation] = []
        for friend in loadedFriends {
            let last = try? await MessagesService.loadLastMessage(meId: meId, friendId: friend.id)
            loaded.append(Conversation(friend: friend, lastMessage: last, unreadCount: unread[friend.id] ?? 0))
        }

        conversations = loaded.sorted { lhs, rhs in
            switch (lhs.lastMessage?.createdAt, rhs.lastMessage?.createdAt) {
            case let (l?, r?): return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.friend.displayName < rhs.friend.displayName
            }
        }
        loading = false
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: conversation.friend.profile, size: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.friend.displayName)
                    .font(Theme.Font.body(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(conversation.lastMessage?.body ?? "Say hi 👋")
                    .font(Theme.Font.body(12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let createdAt = conversation.lastMessage?.createdAt {
                    Text(createdAt.relativeLabel)
                        .font(Theme.Font.body(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(Theme.Font.body(10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.coral, in: Capsule())
                }
            }
        }
        .padding(12)
        .floatingCard(radius: 20)
    }
}

private struct GroupRow: View {
    let group: ChatGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 50, height: 50)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(Theme.Font.body(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(group.members.count) people")
                    .font(Theme.Font.body(12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()
        }
        .padding(12)
        .floatingCard(radius: 20)
    }
}
