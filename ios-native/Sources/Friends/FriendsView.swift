import SwiftUI

/// The Friends tab — everyone you already share with, reusing the exact same
/// `FriendsService.load` the map trusts (never the raw `locations` table, so
/// Ghost Mode masking still applies here too).
struct FriendsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [Friend] = []
    @State private var requests: [FriendRequest] = []
    @State private var busyRequestIds: Set<UUID> = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var selected: Friend?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if loading {
                    ProgressView().tint(Theme.violet)
                } else if friends.isEmpty && requests.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            if !requests.isEmpty {
                                requestsSection
                            }
                            ForEach(friends) { friend in
                                FriendRow(friend: friend)
                                    .onTapGesture {
                                        Haptics.shared.play(.tap)
                                        selected = friend
                                    }
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                }

                if let errorMessage {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .font(Theme.Font.body(12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Theme.coral, in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .task { await reload() }
        .sheet(item: $selected) { friend in
            PersonCard(friend: friend) { throwable, _ in
                Task { try? await SocialService.throwEmoji(throwable.emoji, to: friend.id) }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
        }
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FRIEND REQUESTS · \(requests.count)")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.1)
                .foregroundStyle(Theme.pink)

            ForEach(requests) { request in
                let busy = busyRequestIds.contains(request.relId)
                HStack(spacing: 12) {
                    AvatarView(profile: request.profile, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.profile.displayName)
                            .font(Theme.Font.body(14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("@\(request.profile.username) wants to be your friend")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button {
                        Task { await respond(request, accept: false) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 34, height: 34)
                            .background(Color(hex: 0xF4F0F6), in: Circle())
                    }
                    .disabled(busy)
                    .pressable()
                    Button {
                        Task { await respond(request, accept: true) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.brandGradient, in: Circle())
                    }
                    .disabled(busy)
                    .pressable()
                }
                .padding(12)
                .floatingCard(radius: 20)
                .opacity(busy ? 0.5 : 1)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("🫂").font(.system(size: 44))
            Text("No friends yet")
                .font(Theme.Font.body(15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Head to Explore to share your invite link.")
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func reload() async {
        guard let id = auth.profile?.id else { return }
        loading = friends.isEmpty && requests.isEmpty
        do {
            async let friendsTask = FriendsService.load(for: id)
            async let requestsTask = FriendsService.loadRequests(for: id)
            let (loadedFriends, loadedRequests) = try await (friendsTask, requestsTask)
            friends = loadedFriends.sorted { lhs, rhs in
                if lhs.isBestFriend != rhs.isBestFriend { return lhs.isBestFriend }
                return lhs.streakDays > rhs.streakDays
            }
            requests = loadedRequests
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load friends — pull to try again."
        }
        loading = false
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        busyRequestIds.insert(request.relId)
        defer { busyRequestIds.remove(request.relId) }
        do {
            try await FriendsService.respond(request.relId, accept: accept)
            requests.removeAll { $0.relId == request.relId }
            if accept, let id = auth.profile?.id {
                friends = (try? await FriendsService.load(for: id)) ?? friends
            }
        } catch {
            errorMessage = "Couldn't update that request — try again."
        }
    }
}

private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: friend.profile, size: 50)
                .overlay(
                    Circle()
                        .stroke(friend.isLive ? Color(hex: 0x25CC92) : Color(hex: 0xC4BCD0), lineWidth: 3)
                        .padding(-3)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(friend.displayName)
                        .font(Theme.Font.body(15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if friend.isBestFriend {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.yellow)
                    }
                }
                Text(friend.isLive ? "Live now" : "@\(friend.profile.username)")
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(friend.isLive ? Color(hex: 0x25CC92) : Theme.muted)
            }

            Spacer()

            if friend.streakDays > 0 {
                Label("\(friend.streakDays)", systemImage: "flame.fill")
                    .font(Theme.Font.body(12, weight: .heavy))
                    .foregroundStyle(Theme.coral)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.coral.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .floatingCard(radius: 20)
    }
}
