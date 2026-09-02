import CoreLocation
import MapKit
import SwiftUI
import WidgetKit

/// The home screen: friends on a live MapKit map.
///
/// MapKit rather than Leaflet-in-a-WebView is most of the "feels native" win —
/// momentum scrolling, rotation, and the Look Around/Maps handoff all come free.
struct MapScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location

    @State private var friends: [Friend] = []
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selected: Friend?
    @State private var showBump = false
    @State private var showNotifications = false
    @State private var notificationCount = 0
    @State private var toast: String?
    @State private var knock = KnockDetector()
    @State private var flight: (emoji: String, power: Double, id: UUID)?
    @State private var activeDockSheet: DockSheet?

    @State private var highlightsByUser: [UUID: [Highlight]] = [:]
    @State private var showPostHighlight = false
    @State private var viewingHighlightsFor: HighlightViewerTarget?

    private struct HighlightViewerTarget: Identifiable {
        let profile: Profile
        let isMine: Bool
        var id: UUID { profile.id }
    }

    private enum DockSheet: String, Identifiable {
        case friends, explore, me, messages
        var id: String { rawValue }
    }

    var body: some View {
        Map(position: $camera, selection: Binding(
            get: { selected?.id },
            set: { id in selected = friends.first { $0.id == id } }
        )) {
            UserAnnotation()
            ForEach(friends) { friend in
                if let coordinate = friend.location?.coordinate {
                    Annotation(friend.displayName, coordinate: coordinate) {
                        FriendPin(friend: friend)
                            .onTapGesture {
                                Haptics.shared.play(.tap)
                                selected = friend
                            }
                    }
                    .tag(friend.id)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapUserLocationButton() }
        .overlay {
            if let flight {
                ThrowFlightView(emoji: flight.emoji, power: flight.power)
                    .id(flight.id)
            }
        }
        .ignoresSafeArea()
        // `.safeAreaInset`, not a ZStack sibling, is what keeps this content
        // clear of the status bar/Dynamic Island and the home-indicator
        // gesture strip. A plain ZStack sibling of a view that calls
        // `.ignoresSafeArea()` loses safe-area awareness too — the whole
        // stack's bounds expand to match its full-bleed child, so `.top`/
        // `.bottom` alignment on siblings ends up measured from the true
        // screen edge instead of the safe one. That's why the toast and the
        // profile card were drifting up under the notch, and — more
        // seriously — why the dock's buttons stopped registering taps at
        // all: they were rendering underneath the strip iOS reserves for the
        // home-indicator swipe gesture, which steals touches there before
        // your buttons ever see them. `.safeAreaInset` reserves real,
        // touchable safe-area space for this content instead.
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                topBar
                if let profile = auth.profile {
                    HighlightsRailView(
                        me: profile,
                        friends: friends,
                        highlightsByUser: highlightsByUser,
                        onAddMine: { showPostHighlight = true },
                        onOpen: { userId in
                            if userId == profile.id {
                                viewingHighlightsFor = .init(profile: profile, isMine: true)
                            } else if let friend = friends.first(where: { $0.id == userId }) {
                                viewingHighlightsFor = .init(profile: friend.profile, isMine: false)
                            }
                        }
                    )
                }
                if let toast {
                    Text(toast)
                        .font(Theme.Font.body(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Theme.ink.opacity(0.92), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { dock }
        .sheet(item: $selected) { friend in
            PersonCard(friend: friend) { throwable, power in
                throwAt(friend, throwable, power)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
        }
        .fullScreenCover(isPresented: $showBump) {
            BumpView { met in show("You met \(met.name) 🎉") }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView(onFocusEvent: { lat, lng in
                showNotifications = false
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }, onOpenChat: { friendId in
                showNotifications = false
                if let friend = friends.first(where: { $0.id == friendId }) {
                    selected = friend
                }
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeDockSheet) { sheet in
            Group {
                switch sheet {
                case .friends: FriendsView()
                case .explore: ExploreView()
                case .me: MeView()
                case .messages: MessagesView()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPostHighlight) {
            PostHighlightView(fix: location.current) { Task { await loadHighlights() } }
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
        }
        // Shake anywhere on the map waves at everyone.
        .onShake { Task { await waveAll() } }
        .task {
            if let id = auth.profile?.id {
                location.start(for: id)
                await reload(id)
                await refreshNotificationCount(id)
                await loadHighlights()
            }
            // Two knocks = wave, three = open bump.
            knock.start { count in
                if count >= 3 { showBump = true }
                else { Task { await waveAll() } }
            }
        }
        .onDisappear { knock.stop() }
        .onChange(of: DeepLink.shared.pending) { _, new in
            switch new {
            case .bump:
                showBump = true
                DeepLink.shared.pending = nil
            case .addFriend:
                // ExploreView reads and clears `DeepLink.shared.pending`
                // itself once it appears, so it can prefill the username.
                activeDockSheet = .explore
            case nil:
                break
            }
        }
        // Requests/messages/reactions change while sheets are open — recount
        // the bell badge whenever one closes rather than polling.
        .onChange(of: activeDockSheet) { _, new in
            if new == nil, let id = auth.profile?.id { Task { await refreshNotificationCount(id) } }
        }
        .onChange(of: showNotifications) { _, open in
            if !open, let id = auth.profile?.id { Task { await refreshNotificationCount(id) } }
        }
    }

    private var topBar: some View {
        HStack {
            if let profile = auth.profile {
                HStack(spacing: 9) {
                    AvatarView(profile: profile, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayName)
                            .font(Theme.Font.body(13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(profile.statusText ?? "Sharing live")
                            .font(Theme.Font.body(10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .floatingCard(radius: 22)
            }
            Spacer()
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .floatingCard(radius: 22)
                    if notificationCount > 0 {
                        Text(notificationCount > 9 ? "9+" : "\(notificationCount)")
                            .font(Theme.Font.body(9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.coral, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .pressable()
            Button { showBump = true } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .floatingCard(radius: 22)
            }
            .pressable()
        }
        .padding(.horizontal, 14)
    }

    private var dock: some View {
        HStack(spacing: 0) {
            dockButton("person.2.fill", "Friends") { activeDockSheet = .friends }
            dockButton("magnifyingglass", "Explore") { activeDockSheet = .explore }
            Button {
                Task { await waveAll() }
            } label: {
                Text("👋").font(.system(size: 26))
                    .frame(width: 52, height: 52)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.pink.opacity(0.34), radius: 12, y: 6)
            }
            .pressable(scale: 0.9)
            .frame(maxWidth: .infinity)
            dockButton("person.crop.circle", "Me") { activeDockSheet = .me }
            dockButton("bubble.left.fill", "Messages") { activeDockSheet = .messages }
        }
        .padding(6)
        .floatingCard(radius: 28)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func dockButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(label).font(Theme.Font.body(10, weight: .heavy))
            }
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
        }
        .pressable()
    }

    // MARK: - Actions

    private func reload(_ userId: UUID) async {
        friends = (try? await FriendsService.load(for: userId)) ?? []
        publishWidgetSnapshot()
    }

    private func loadHighlights() async {
        highlightsByUser = (try? await HighlightsService.loadFriendHighlights()) ?? [:]
    }

    /// Badge count: pending requests + unread messages — the two that mean
    /// "something needs your attention" rather than just "something happened".
    private func refreshNotificationCount(_ userId: UUID) async {
        async let requests = (try? FriendsService.loadRequests(for: userId)) ?? []
        async let unread = (try? MessagesService.loadUnreadCounts(for: userId)) ?? [:]
        let (r, u) = await (requests, unread)
        notificationCount = r.count + u.values.reduce(0, +)
    }

    /// Hand the home-screen widget a fresh snapshot. The widget never queries
    /// Supabase itself — see `NearbySnapshot`.
    private func publishWidgetSnapshot() {
        guard let mine = location.current else { return }
        let origin = CLLocation(latitude: mine.lat, longitude: mine.lng)
        let entries: [NearbySnapshot.Entry] = friends.compactMap { friend in
            guard friend.isLive, let theirs = friend.location else { return nil }
            let metres = origin.distance(
                from: CLLocation(latitude: theirs.lat, longitude: theirs.lng)
            )
            return .init(name: friend.displayName, distance: metres)
        }
        NearbySnapshot.save(entries)
        WidgetCenter.shared.reloadTimelines(ofKind: "NearbyFriends")
    }

    private func waveAll() async {
        guard let count = try? await SocialService.waveAtEveryone() else { return }
        Haptics.shared.play(.success)
        show(count > 0 ? "Waved at \(count) friends 👋" : "No friends to wave at yet")
    }

    private func throwAt(_ friend: Friend, _ throwable: Throwable, _ power: Double) {
        flight = (throwable.emoji, power, UUID())
        Task {
            try? await SocialService.throwEmoji(throwable.emoji, to: friend.id)
            try? await Task.sleep(for: .seconds(1))
            flight = nil
        }
    }

    private func show(_ message: String) {
        withAnimation(.spring(duration: 0.3)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toast = nil }
        }
    }
}

/// A friend's map pin. Green ring = live, grey = hidden or stale — the same
/// language as the web app.
struct FriendPin: View {
    let friend: Friend

    var body: some View {
        AvatarView(profile: friend.profile, size: 46)
            .overlay(
                Circle().stroke(friend.isLive ? Color(hex: 0x25CC92) : Color(hex: 0xC4BCD0), lineWidth: 3)
                    .padding(-4)
            )
            .shadow(color: Theme.ink.opacity(0.22), radius: 10, y: 5)
    }
}

struct AvatarView: View {
    let profile: Profile
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.violet.opacity(0.9))
            if let urlString = profile.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
    }

    private var initial: some View {
        Text(profile.displayName.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
