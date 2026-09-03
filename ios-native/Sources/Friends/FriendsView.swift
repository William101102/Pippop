import CoreLocation
import SwiftUI

/// The Friends sheet — a direct port of the web app's Friends panel, which is
/// where the Highlights rail actually lives (the native build had put that
/// rail on the map screen, where the web app has never shown it).
///
/// Uses the exact same `FriendsService.load` the map trusts — never the raw
/// `locations` table, so Ghost Mode masking still applies here too.
struct FriendsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [Friend] = []
    @State private var requests: [FriendRequest] = []
    @State private var busyRequestIds: Set<UUID> = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var query = ""

    @State private var highlightsByUser: [UUID: [Highlight]] = [:]
    @State private var route: Route?
    @State private var viewingHighlightsFor: HighlightViewerTarget?

    private enum Route: Identifiable {
        case person(Friend)
        case postHighlight

        var id: String {
            switch self {
            case let .person(friend): "person-\(friend.id)"
            case .postHighlight: "post-highlight"
            }
        }
    }

    private struct HighlightViewerTarget: Identifiable {
        let profile: Profile
        let isMine: Bool
        var id: UUID { profile.id }
    }

    private var shown: [Friend] {
        guard !query.isEmpty else { return friends }
        let needle = query.lowercased()
        return friends.filter {
            $0.displayName.lowercased().contains(needle) || $0.profile.username.lowercased().contains(needle)
        }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if let profile = auth.profile {
                        HighlightsRailView(
                            me: profile,
                            friends: friends,
                            highlightsByUser: highlightsByUser,
                            onAddMine: { route = .postHighlight },
                            onOpen: { userId in
                                if userId == profile.id {
                                    viewingHighlightsFor = .init(profile: profile, isMine: true)
                                } else if let friend = friends.first(where: { $0.id == userId }) {
                                    viewingHighlightsFor = .init(profile: friend.profile, isMine: false)
                                }
                            }
                        )
                    }

                    if !requests.isEmpty { requestsSection }

                    searchField

                    if loading {
                        ProgressView().tint(Theme.violet)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else if friends.isEmpty {
                        empty
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { friend in
                                FriendRow(friend: friend, myFix: location.current)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Haptics.shared.play(.tap)
                                        route = .person(friend)
                                    }
                            }
                        }
                        if shown.isEmpty {
                            Text("No results for \"\(query)\"")
                                .font(Theme.Font.body(12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .refreshable { await reload() }

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
        .task {
            await reload()
            await loadHighlights()
        }
        .sheet(item: $route) { route in
            switch route {
            case let .person(friend):
                PersonCard(friend: friend) { throwable, _ in
                    Task { try? await SocialService.throwEmoji(throwable.emoji, to: friend.id) }
                }
                .themedPresentation()
                .presentationDetents([.fraction(0.69), .large])
                .presentationCornerRadius(30)
                .presentationDragIndicator(.visible)
            case .postHighlight:
                PostHighlightView(fix: location.current) { Task { await loadHighlights() } }
                    .themedPresentation()
            }
        }
        .fullScreenCover(item: $viewingHighlightsFor) { target in
            HighlightViewerView(
                author: target.profile,
                isMine: target.isMine,
                highlights: highlightsByUser[target.profile.id] ?? [],
                onDelete: { id in
                    Task {
                        try? await HighlightsService.delete(id)
                        await loadHighlights()
                    }
                }
            )
            .themedPresentation()
        }
    }

    /// `.sheet-head` — a pink eyebrow, a big Fredoka count, and a round close
    /// button on `--fill`, instead of a UIKit navigation bar.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR CIRCLE")
                    .font(Theme.Font.body(10, weight: .heavy))
                    .kerning(1.3)
                    .foregroundStyle(Theme.pink)
                Text(friends.count == 1 ? "1 friend" : "\(friends.count) friends")
                    .font(Theme.Font.display(28))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 34)
                    .background(Theme.fill, in: Circle())
            }
            .pressable()
        }
    }

    /// `.search` — a filled pill, not a bordered text field.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
            TextField("Search friends", text: $query)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tint(Theme.violet)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// `.requests-inbox` — a single soft gradient block holding every pending
    /// request, rather than one floating card each.
    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRIEND REQUESTS · \(requests.count)")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.1)
                .foregroundStyle(Theme.pink)

            ForEach(requests) { request in
                let busy = busyRequestIds.contains(request.relId)
                HStack(spacing: 11) {
                    AvatarView(profile: request.profile, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.profile.displayName)
                            .font(Theme.Font.body(14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("@\(request.profile.username) wants to be your friend")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button { Task { await respond(request, accept: false) } } label: {
                        Text("Ignore")
                            .font(Theme.Font.body(11, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(busy)
                    .pressable()
                    Button { Task { await respond(request, accept: true) } } label: {
                        Text("Add")
                            .font(Theme.Font.body(11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(busy)
                    .pressable()
                }
                .opacity(busy ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Theme.adaptive(light: 0xFFF2EC, dark: 0x33262C), Theme.adaptive(light: 0xF1ECFF, dark: 0x272040)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    private func loadHighlights() async {
        highlightsByUser = (try? await HighlightsService.loadFriendHighlights()) ?? [:]
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

/// Port of `.friend-row` — a flat, transparent row (the web app's friend list
/// is not a stack of floating cards), with the status emoji on the avatar, a
/// best-friend star, an inline streak chip, and distance/battery on the right.
private struct FriendRow: View {
    let friend: Friend
    let myFix: Fix?

    private var distanceText: String? {
        guard let myFix, let theirs = friend.location else { return nil }
        return Fmt.distance(from: myFix.coordinate, to: theirs.coordinate)
    }

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(profile: friend.profile, size: 46, showStatus: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if friend.isBestFriend {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xF5B323))
                    }
                    Text(friend.displayName)
                        .font(Theme.Font.body(14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    StreakChip(info: friend.streak)
                }
                Text(statusLine)
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                if let distanceText {
                    Text(distanceText)
                        .font(Theme.Font.body(10, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                }
                if let battery = friend.profile.batteryLevel {
                    HStack(spacing: 3) {
                        if friend.profile.isCharging == true {
                            Image(systemName: "bolt.fill").font(.system(size: 8))
                        }
                        Text("\(battery)%")
                    }
                    .font(Theme.Font.body(10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 10)
    }

    private var statusLine: String {
        let handle = "@\(friend.profile.username)"
        guard let status = friend.profile.statusText, !status.isEmpty else { return handle }
        return "\(handle) · \(status)"
    }
}

/// Port of `.streak-chip` — the compact inline form of the streak badge used
/// in list rows, as opposed to `StreakBadge`'s full-width version on the
/// person card.
struct StreakChip: View {
    let info: StreakInfo
    @State private var pulse = false

    var body: some View {
        Group {
            if info.repairing {
                chip("🩹\(info.repairDaysLeft)", fg: Theme.infoInk, bg: AnyShapeStyle(Theme.infoSoft))
            } else if info.canRepair {
                chip("💔", fg: Theme.dangerInk, bg: AnyShapeStyle(Theme.dangerSoft))
                    .opacity(pulse ? 0.55 : 1)
                    .onAppear { startPulse() }
            } else if info.days > 0 {
                chip(
                    "\(info.icon)\(info.days)",
                    fg: info.atRisk ? Theme.dangerInk : Theme.warnInk,
                    bg: info.atRisk
                        ? AnyShapeStyle(Theme.dangerSoft)
                        : (info.tier == .blaze || info.tier == .legend
                            ? AnyShapeStyle(Theme.streakHotGradient)
                            : AnyShapeStyle(Theme.warnSoft))
                )
                .opacity(info.atRisk && pulse ? 0.55 : 1)
                .onAppear { if info.atRisk { startPulse() } }
            }
        }
    }

    private func chip(_ text: String, fg: Color, bg: AnyShapeStyle) -> some View {
        Text(text)
            .font(Theme.Font.body(9.5, weight: .heavy))
            .foregroundStyle(fg)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(bg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
    }
}
