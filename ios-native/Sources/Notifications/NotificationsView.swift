import SwiftUI

/// The bell-icon panel — friend requests, unread message previews, reactions
/// received, and friends' recent arrivals/departures. Port of the web app's
/// `NotificationsPanel`.
struct NotificationsView: View {
    var onFocusEvent: (Double, Double) -> Void
    var onOpenChat: (UUID) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var requests: [FriendRequest] = []
    @State private var unreadPreviews: [(friend: Friend, count: Int, last: Message?)] = []
    @State private var reactions: [MapReaction] = []
    @State private var placeEvents: [PlaceEvent] = []
    @State private var friendNameById: [UUID: String] = [:]
    @State private var busyRequestIds: Set<UUID> = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if loading {
                    ProgressView().tint(Theme.violet)
                } else if isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !requests.isEmpty { requestsSection }
                            if !unreadPreviews.isEmpty { messagesSection }
                            if !reactions.isEmpty { reactionsSection }
                            if !placeEvents.isEmpty { activitySection }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .task { await reload() }
    }

    private var isEmpty: Bool {
        requests.isEmpty && unreadPreviews.isEmpty && reactions.isEmpty && placeEvents.isEmpty
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("🔔").font(.system(size: 44))
            Text("You're all caught up")
                .font(Theme.Font.body(15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Friend requests, waves, and check-ins will show up here.")
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func sectionHeader(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.Font.body(10, weight: .heavy))
            .kerning(1.1)
            .foregroundStyle(Theme.pink)
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("person.badge.plus", "FRIEND REQUESTS")
            ForEach(requests) { request in
                let busy = busyRequestIds.contains(request.relId)
                HStack(spacing: 12) {
                    AvatarView(profile: request.profile, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.profile.displayName)
                            .font(Theme.Font.body(13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("@\(request.profile.username)")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button {
                        Task { await respond(request, accept: false) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 30, height: 30)
                            .background(Color(hex: 0xF4F0F6), in: Circle())
                    }
                    .disabled(busy)
                    .pressable()
                    Button {
                        Task { await respond(request, accept: true) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.brandGradient, in: Circle())
                    }
                    .disabled(busy)
                    .pressable()
                }
                .padding(10)
                .floatingCard(radius: 18)
                .opacity(busy ? 0.5 : 1)
            }
        }
    }

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("message.fill", "UNREAD MESSAGES")
            ForEach(unreadPreviews, id: \.friend.id) { preview in
                Button { onOpenChat(preview.friend.id) } label: {
                    HStack(spacing: 12) {
                        AvatarView(profile: preview.friend.profile, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.friend.displayName)
                                .font(Theme.Font.body(13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text(preview.last?.body ?? "New message")
                                .font(Theme.Font.body(11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(preview.count)")
                                .font(Theme.Font.body(10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.coral, in: Capsule())
                            if let createdAt = preview.last?.createdAt {
                                Text(createdAt.relativeLabel)
                                    .font(Theme.Font.body(9, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(10)
                    .floatingCard(radius: 18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("heart.fill", "REACTIONS RECEIVED")
            ForEach(reactions.prefix(8)) { reaction in
                HStack(spacing: 12) {
                    Text(reaction.emoji).font(.system(size: 26))
                        .frame(width: 42, height: 42)
                        .background(Color(hex: 0xF4F0F6), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friendNameById[reaction.senderId] ?? "A friend")
                            .font(Theme.Font.body(13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("sent you \(reaction.emoji)")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(reaction.createdAt.relativeLabel)
                        .font(Theme.Font.body(10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(10)
                .floatingCard(radius: 18)
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("mappin.circle.fill", "FRIEND ACTIVITY")
            ForEach(placeEvents.prefix(10)) { event in
                Button {
                    if let lat = event.lat, let lng = event.lng { onFocusEvent(lat, lng) }
                } label: {
                    HStack(spacing: 12) {
                        Text(event.kind == .arrive ? "📍" : "🚶").font(.system(size: 22))
                            .frame(width: 42, height: 42)
                            .background(Color(hex: 0xF4F0F6), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friendNameById[event.userId] ?? "A friend")
                                .font(Theme.Font.body(13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text("\(event.kind == .arrive ? "arrived at" : "left") \(event.label.isEmpty ? "a place" : event.label)")
                                .font(Theme.Font.body(11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(event.createdAt.relativeLabel)
                            .font(Theme.Font.body(10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(10)
                    .floatingCard(radius: 18)
                }
                .buttonStyle(.plain)
                .disabled(event.lat == nil || event.lng == nil)
            }
        }
    }

    private func reload() async {
        guard let meId = auth.profile?.id else { return }
        loading = requests.isEmpty && unreadPreviews.isEmpty && reactions.isEmpty && placeEvents.isEmpty

        async let friendsTask = FriendsService.load(for: meId)
        async let requestsTask = FriendsService.loadRequests(for: meId)
        async let unreadCountsTask = MessagesService.loadUnreadCounts(for: meId)
        async let reactionsTask = SocialService.loadMyReactions(for: meId)
        async let placeEventsTask = SocialService.loadPlaceEvents()

        let friends = (try? await friendsTask) ?? []
        requests = (try? await requestsTask) ?? []
        let unreadCounts = (try? await unreadCountsTask) ?? [:]
        reactions = (try? await reactionsTask) ?? []
        placeEvents = (try? await placeEventsTask) ?? []

        friendNameById = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0.displayName) })

        var previews: [(friend: Friend, count: Int, last: Message?)] = []
        for friend in friends {
            guard let count = unreadCounts[friend.id], count > 0 else { continue }
            let last = try? await MessagesService.loadLastMessage(meId: meId, friendId: friend.id)
            previews.append((friend, count, last))
        }
        unreadPreviews = previews

        loading = false
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        busyRequestIds.insert(request.relId)
        defer { busyRequestIds.remove(request.relId) }
        try? await FriendsService.respond(request.relId, accept: accept)
        requests.removeAll { $0.relId == request.relId }
    }
}
