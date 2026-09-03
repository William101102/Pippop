import SwiftUI

/// Ids of notifications this device has swiped away.
///
/// Reactions and arrival/departure events have nothing server-side to mark as
/// "seen" — reactions expire after an hour, place events are only queried for
/// the last 12 — so dismissing them is a local decision, remembered here so a
/// cleared list doesn't refill itself on the next open.
enum DismissedNotifications {
    private static let key = "pinpop-dismissed-notifications"
    /// Enough to cover every row that could still be in range, without
    /// growing without bound.
    private static let cap = 300

    static func load() -> Set<UUID> {
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(stored.compactMap(UUID.init(uuidString:)))
    }

    static func add(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        stored.append(contentsOf: ids.map(\.uuidString))
        if stored.count > cap { stored.removeFirst(stored.count - cap) }
        UserDefaults.standard.set(stored, forKey: key)
    }
}

/// The bell-icon panel — friend requests, unread message previews, reactions
/// received, and friends' recent arrivals/departures. Port of the web app's
/// `NotificationsPanel`, plus swipe-to-clear and a clear-all button.
struct NotificationsView: View {
    var onFocusEvent: (Double, Double) -> Void
    var onOpenChat: (UUID) -> Void
    /// Pushes the panel's own visible count up to the bell badge, so the two
    /// can never disagree — the badge used to be recounted independently and
    /// could sit at "2" with nothing on screen to clear.
    var onCountChange: (Int) -> Void = { _ in }

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var requests: [FriendRequest] = []
    @State private var unreadPreviews: [(friend: Friend, count: Int, last: Message?)] = []
    @State private var reactions: [MapReaction] = []
    @State private var placeEvents: [PlaceEvent] = []
    @State private var friendNameById: [UUID: String] = [:]
    @State private var busyRequestIds: Set<UUID> = []
    @State private var loading = true
    @State private var dismissedIds: Set<UUID> = DismissedNotifications.load()

    private var shownReactions: [MapReaction] {
        Array(reactions.filter { !dismissedIds.contains($0.id) }.prefix(8))
    }

    private var shownEvents: [PlaceEvent] {
        Array(placeEvents.filter { !dismissedIds.contains($0.id) }.prefix(10))
    }

    private var isEmpty: Bool {
        requests.isEmpty && unreadPreviews.isEmpty && shownReactions.isEmpty && shownEvents.isEmpty
    }

    /// Everything except friend requests: those need an actual answer, so
    /// "clear all" must never silently decline them.
    private var hasClearableRows: Bool {
        !unreadPreviews.isEmpty || !shownReactions.isEmpty || !shownEvents.isEmpty
    }

    /// What the bell badge should read: the rows that actually need you, and
    /// only ones this panel is showing.
    private var visibleCount: Int {
        requests.count + unreadPreviews.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if loading {
                    ProgressView().tint(Theme.violet)
                } else if isEmpty {
                    empty
                } else {
                    List {
                        if !requests.isEmpty {
                            Section {
                                ForEach(requests) { request in
                                    requestRow(request)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task { await respond(request, accept: false) }
                                            } label: {
                                                Label("Ignore", systemImage: "xmark")
                                            }
                                        }
                                }
                            } header: {
                                sectionHeader("person.badge.plus", "FRIEND REQUESTS")
                            }
                        }

                        if !unreadPreviews.isEmpty {
                            Section {
                                ForEach(unreadPreviews, id: \.friend.id) { preview in
                                    messageRow(preview)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button {
                                                Task { await markRead(preview.friend.id) }
                                            } label: {
                                                Label("Mark read", systemImage: "envelope.open")
                                            }
                                            .tint(Theme.violet)
                                        }
                                }
                            } header: {
                                sectionHeader("message.fill", "UNREAD MESSAGES")
                            }
                        }

                        if !shownReactions.isEmpty {
                            Section {
                                ForEach(shownReactions) { reaction in
                                    reactionRow(reaction)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                clear([reaction.id])
                                            } label: {
                                                Label("Clear", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                sectionHeader("heart.fill", "REACTIONS RECEIVED")
                            }
                        }

                        if !shownEvents.isEmpty {
                            Section {
                                ForEach(shownEvents) { event in
                                    activityRow(event)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                clear([event.id])
                                            } label: {
                                                Label("Clear", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                sectionHeader("mappin.circle.fill", "FRIEND ACTIVITY")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear all") { Task { await clearAll() } }
                        .font(Theme.Font.body(14, weight: .bold))
                        .disabled(!hasClearableRows)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .task { await reload() }
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
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Rows

    private func requestRow(_ request: FriendRequest) -> some View {
        let busy = busyRequestIds.contains(request.relId)
        return HStack(spacing: 12) {
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
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            Button {
                Task { await respond(request, accept: true) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(10)
        .floatingCard(radius: 18)
        .opacity(busy ? 0.5 : 1)
    }

    private func messageRow(_ preview: (friend: Friend, count: Int, last: Message?)) -> some View {
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
                        .background(Theme.pink, in: Capsule())
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

    private func reactionRow(_ reaction: MapReaction) -> some View {
        HStack(spacing: 12) {
            Text(reaction.emoji).font(.system(size: 26))
                .frame(width: 42, height: 42)
                .background(Theme.fill, in: Circle())
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

    private func activityRow(_ event: PlaceEvent) -> some View {
        Button {
            if let lat = event.lat, let lng = event.lng { onFocusEvent(lat, lng) }
        } label: {
            HStack(spacing: 12) {
                Text(event.kind == .arrive ? "📍" : "🚶").font(.system(size: 22))
                    .frame(width: 42, height: 42)
                    .background(Theme.fill, in: Circle())
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

    // MARK: - Actions

    private func clear(_ ids: [UUID]) {
        Haptics.shared.play(.tap)
        dismissedIds.formUnion(ids)
        DismissedNotifications.add(ids)
    }

    /// Clears everything that can be cleared without answering for the user:
    /// unread threads get marked read, reactions and activity get dismissed.
    /// Pending friend requests deliberately stay put — they need a real
    /// accept/ignore, and silently declining them on a "clear all" would be
    /// the wrong kind of surprise.
    private func clearAll() async {
        guard let meId = auth.profile?.id else { return }
        Haptics.shared.play(.success)

        // Marks every unread row read, not just the ones with a visible
        // preview — otherwise a message from a non-friend keeps the badge
        // above zero with nothing on screen to clear.
        try? await MessagesService.markAllRead(meId: meId)
        unreadPreviews = []

        let ids = shownReactions.map(\.id) + shownEvents.map(\.id)
        dismissedIds.formUnion(ids)
        DismissedNotifications.add(ids)
        onCountChange(visibleCount)
    }

    private func markRead(_ friendId: UUID) async {
        guard let meId = auth.profile?.id else { return }
        Haptics.shared.play(.tap)
        try? await MessagesService.markThreadRead(meId: meId, friendId: friendId)
        unreadPreviews.removeAll { $0.friend.id == friendId }
        onCountChange(visibleCount)
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
        onCountChange(visibleCount)
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        busyRequestIds.insert(request.relId)
        defer { busyRequestIds.remove(request.relId) }
        try? await FriendsService.respond(request.relId, accept: accept)
        requests.removeAll { $0.relId == request.relId }
        onCountChange(visibleCount)
    }
}
