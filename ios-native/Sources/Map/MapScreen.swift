import CoreLocation
import MapKit
import SwiftUI
import WidgetKit

/// The home screen: friends on a live MapKit map.
///
/// MapKit rather than Leaflet-in-a-WebView is most of the "feels native" win —
/// momentum scrolling, rotation, and the Look Around/Maps handoff all come free.
///
/// Layout mirrors the web app's map screen 1:1 (see `src/styles.css`): a
/// profile chip and two circle buttons on top, the closest-friend `.map-mood`
/// pill under them, a column of `.map-tools` down the right edge, and the
/// `.map-peek` friend carousel sitting directly above the dock.
struct MapScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(ThemeStore.self) private var theme

    @State private var friends: [Friend] = []
    @State private var nightPlaces: [SignificantPlace] = []
    /// "SANTA CLARA" in the top bar — reverse-geocoded from your own fix and
    /// only refreshed once you've actually moved, not on every ping. The
    /// geocoder is held rather than built per call: an inline one gets
    /// released the moment the request suspends, which cancels it.
    @State private var cityName: String?
    @State private var lastGeocodedCoordinate: CLLocationCoordinate2D?
    @State private var geocoder = CLGeocoder()
    /// Deliberately **not** `.userLocation`. Pinning the camera to the user's
    /// location puts MapKit into follow mode, which draws its own system
    /// location puck — a second marker sitting under our avatar pin (tinted
    /// violet by the app's accent colour). Centring on the coordinate by hand
    /// gives the same behaviour with our pin as the only "you" on the map.
    @State private var camera: MapCameraPosition = .automatic
    @State private var hasCentredOnMe = false
    @State private var selected: Friend?
    @State private var showBump = false
    @State private var showNotifications = false
    @State private var notificationCount = 0
    @State private var toast: String?
    @State private var knock = KnockDetector()
    @State private var flight: (emoji: String, power: Double, id: UUID)?
    @State private var activeDockSheet: DockSheet?

    private enum DockSheet: String, Identifiable {
        case friends, explore, me, messages
        var id: String { rawValue }
    }

    var body: some View {
        Map(position: $camera, selection: Binding(
            get: { selected?.id },
            set: { id in selected = friends.first { $0.id == id } }
        )) {
            // You get a real avatar pin, not MapKit's blue dot — both Zenly
            // and the web app draw your own face on the map the same way
            // they draw everyone else's (`.person-pin.mine`).
            if let profile = auth.profile, let mine = location.current {
                // `anchor: .bottom` so the teardrop's tip is what sits on the
                // coordinate, not the middle of the avatar.
                Annotation("You", coordinate: mine.coordinate, anchor: .bottom) {
                    MapAvatarPin(profile: profile, isLive: true, speed: mine.speed)
                        .onTapGesture {
                            Haptics.shared.play(.tap)
                            activeDockSheet = .me
                        }
                }
            }
            ForEach(friends) { friend in
                if let coordinate = friend.location?.coordinate {
                    Annotation(friend.displayName, coordinate: coordinate, anchor: .bottom) {
                        FriendPin(friend: friend)
                            .onTapGesture {
                                Haptics.shared.play(.tap)
                                selected = friend
                            }
                    }
                    .tag(friend.id)
                }
            }
            // Where you (or a friend) sleep — a standing pin, not tied to
            // anyone's live position, same as the web app never drew it but
            // real Zenly always has.
            ForEach(nightPlaces) { place in
                // Empty title on purpose: MapKit draws an annotation's title
                // as a caption under the pin, which stacked a second "Night
                // place" underneath the badge — over the top of the avatar
                // the place almost always sits on. The icon says it.
                Annotation("", coordinate: place.coordinate, anchor: .bottom) {
                    NightPlacePin(place: place)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
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
                if let closest = closestFriend {
                    MapMoodPill(friend: closest.friend, distanceText: closest.distance) {
                        selected = closest.friend
                    }
                }
                if let toast {
                    Text(toast)
                        .font(Theme.Font.body(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Theme.toastBg.opacity(0.92), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let profile = auth.profile {
                    FriendRailView(
                        me: profile,
                        friends: friends,
                        selectedId: selected?.id,
                        onSelectMe: { focusOnMe() },
                        onSelect: { friend in focus(on: friend) },
                        onAdd: { activeDockSheet = .explore }
                    )
                }
                dock
            }
        }
        // `.map-tools` — the web app's own locate/explore buttons, in place of
        // MapKit's default control cluster, so both builds put the same
        // controls in the same corner.
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                MapToolButton(symbol: "location.fill") { focusOnMe() }
                MapToolButton(symbol: "mappin.and.ellipse") { activeDockSheet = .explore }
                // The web app puts a theme toggle here as a third tool; on
                // native it lives in Me → Appearance as a proper three-up
                // picker instead, which shows what each mode looks like
                // rather than making you cycle blind through them.
            }
            .padding(.trailing, 12)
            .padding(.bottom, 168)
        }
        .sheet(item: $selected) { friend in
            PersonCard(friend: friend) { throwable, power in
                throwAt(friend, throwable, power)
            }
            .id(theme.preference)
            // `.person-card { max-height: 69% }` — a partial sheet that keeps
            // the map visible behind it, not a full-screen takeover.
            .presentationDetents([.fraction(0.69), .large])
            .presentationCornerRadius(30)
            .presentationDragIndicator(.visible)
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
            }, onCountChange: { count in
                // The panel is the source of truth for the badge while it's
                // open, so clearing a row updates the bell immediately.
                notificationCount = count
            })
            .id(theme.preference)
            .presentationDetents([.fraction(0.66), .large])
            .presentationCornerRadius(30)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeDockSheet) { sheet in
            Group {
                // Day/Night/Auto lives in Me, and Me updates live while it's
                // open — the map behind it proves that. These other three
                // don't: a `.sheet(item:)` swapping *which* case is shown
                // without the modifier's own presentation ever fully
                // tearing down can leave a freshly-opened Friends/Explore/
                // Messages sheet drawn against the trait collection that was
                // current when it was last built, not the one just picked —
                // hence "only changes if you swipe away and come back".
                // `.id(theme.preference)` forces a clean rebuild against
                // whatever the current preference actually is. Left off
                // `.me` itself so toggling a tile there doesn't reset its
                // own in-progress edits.
                switch sheet {
                case .friends: FriendsView().id(theme.preference)
                case .explore: ExploreView().id(theme.preference)
                case .me: MeView()
                case .messages: MessagesView().id(theme.preference)
                }
            }
            // `.sheet { max-height: 66% }` on the web — the map stays visible
            // above it rather than every panel being a full-screen page.
            .presentationDetents([.fraction(0.66), .large])
            .presentationCornerRadius(30)
            .presentationDragIndicator(.visible)
        }
        // Shake anywhere on the map waves at everyone.
        .onShake { Task { await waveAll() } }
        .task {
            if let id = auth.profile?.id {
                location.start(for: id)
                await reload(id)
                await refreshNotificationCount(id)
            }
            // `LocationService` outlives this screen, so a fix can already be
            // in hand when the map appears — in which case `onChange` has
            // nothing to fire on and the city label would stay empty.
            if let fix = location.current { refreshCityNameIfNeeded(for: fix) }
            // Two knocks = wave, three = open bump.
            knock.start { count in
                if count >= 3 { showBump = true }
                else { Task { await waveAll() } }
            }
        }
        .onDisappear { knock.stop() }
        // First fix of the session centres the map — after that the camera is
        // the user's to move, so this only ever fires once.
        .onChange(of: location.current) { _, fix in
            guard let fix else { return }
            refreshCityNameIfNeeded(for: fix)
            guard !hasCentredOnMe else { return }
            hasCentredOnMe = true
            withAnimation {
                camera = .region(MKCoordinateRegion(
                    center: fix.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))
            }
        }
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

    /// `.profile-chip` — on a phone the web app hides the name/status text
    /// (`.profile-chip > div { display: none }`), leaving just your avatar
    /// and a chevron, so this does the same rather than carrying a name and
    /// a "Sharing live" line the web build never shows at this width.
    private var topBar: some View {
        HStack(spacing: 8) {
            if let profile = auth.profile {
                Button { activeDockSheet = .me } label: {
                    HStack(spacing: 4) {
                        AvatarView(profile: profile, size: 38)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .padding(.trailing, 4)
                    }
                    .padding(5)
                    .floatingCard(radius: 22, style: .glass)
                }
                .pressable()
            }
            Spacer()
            if let cityName {
                Text(cityName.uppercased())
                    .font(Theme.Font.display(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .floatingCard(radius: 16, style: .glass)
                Spacer()
            }
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 45, height: 45)
                        .floatingCard(radius: 23, style: .glass)
                    if notificationCount > 0 {
                        Text(notificationCount > 9 ? "9+" : "\(notificationCount)")
                            .font(Theme.Font.body(9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.pink, in: Capsule())
                            .overlay(Capsule().stroke(.white, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .pressable()
            Button { showBump = true } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 45, height: 45)
                    .floatingCard(radius: 23, style: .glass)
            }
            .pressable()
        }
        .padding(.horizontal, 12)
    }

    private var dock: some View {
        HStack(spacing: 0) {
            // Outline glyphs, matching the web app's lucide icon set — the
            // filled SF Symbols this used before read much heavier.
            dockButton("person.2", "Friends", isActive: activeDockSheet == .friends) { activeDockSheet = .friends }
            dockButton("magnifyingglass", "Explore", isActive: activeDockSheet == .explore) { activeDockSheet = .explore }
            Button {
                Task { await waveAll() }
            } label: {
                Text("👋").font(.system(size: 26))
                    .frame(width: 52, height: 52)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color(hex: 0xFF4969).opacity(0.34), radius: 9, y: 8)
            }
            .pressable(scale: 0.9)
            .frame(maxWidth: .infinity)
            dockButton("person", "Me", isActive: activeDockSheet == .me) { activeDockSheet = .me }
            dockButton("message", "Messages", isActive: activeDockSheet == .messages) { activeDockSheet = .messages }
        }
        .padding(6)
        .floatingCard(radius: 28, style: .dock)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    /// Port of `.dock button` — resting color is a dedicated grey
    /// (`Theme.dockInactive`), never `--muted`, and the active tab gets a
    /// soft violet pill behind it rather than just a color change.
    private func dockButton(_ symbol: String, _ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(label).font(Theme.Font.body(10, weight: .heavy))
            }
            .foregroundStyle(isActive ? Theme.violet : Theme.dockInactive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .pressable()
    }

    // MARK: - Derived state

    /// The friend the `.map-mood` pill is about: the nearest one still
    /// sharing a live position.
    private var closestFriend: (friend: Friend, distance: String)? {
        guard let mine = location.current else { return nil }
        let origin = CLLocation(latitude: mine.lat, longitude: mine.lng)
        let candidates: [(Friend, CLLocationDistance)] = friends.compactMap { friend in
            guard friend.isLive, let theirs = friend.location else { return nil }
            return (friend, origin.distance(from: CLLocation(latitude: theirs.lat, longitude: theirs.lng)))
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return (nearest.0, Fmt.distance(nearest.1))
    }

    // MARK: - Actions

    private func focusOnMe() {
        Haptics.shared.play(.tap)
        selected = nil
        guard let mine = location.current else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: mine.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    private func focus(on friend: Friend) {
        Haptics.shared.play(.tap)
        selected = friend
        guard let coordinate = friend.location?.coordinate else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
    }

    private func reload(_ userId: UUID) async {
        async let friendsTask = FriendsService.load(for: userId)
        async let placesTask = (try? PlacesService.loadVisible()) ?? []
        friends = (try? await friendsTask) ?? []
        nightPlaces = await placesTask
        publishWidgetSnapshot()
    }

    /// Reverse-geocodes only after a real move (2 km), not on every fix —
    /// `CLGeocoder` is rate-limited, and "Santa Clara" doesn't need re-asking
    /// every 25 metres. The distance guard is skipped while there's still no
    /// name on screen, so a first attempt that failed gets another go on the
    /// next fix rather than leaving the bar empty for the whole session.
    @MainActor
    private func refreshCityNameIfNeeded(for fix: Fix) {
        let coordinate = fix.coordinate
        if cityName != nil, let last = lastGeocodedCoordinate {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard moved > 2000 else { return }
        }
        // A second request on the same geocoder cancels the first.
        guard !geocoder.isGeocoding else { return }
        lastGeocodedCoordinate = coordinate

        Task { @MainActor in
            // Two things this needs that the first cut got wrong, and why the
            // label never appeared: the geocoder has to outlive the await (a
            // `CLGeocoder()` built inline is released the moment the call
            // suspends, which cancels the request), and the result has to be
            // written back on the main actor — a bare `Task {}` in a
            // non-isolated method hops off it.
            let placemarks = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            guard let place = placemarks?.first else { return }
            cityName = place.locality
                ?? place.subLocality
                ?? place.subAdministrativeArea
                ?? place.administrativeArea
                ?? place.name
        }
    }

    /// Badge count: pending requests + unread messages — the two that mean
    /// "something needs your attention" rather than just "something happened".
    ///
    /// Only counts unread from people the notifications panel will actually
    /// list. `loadUnreadCounts` returns rows from *anyone*, so counting it
    /// raw left the badge stuck at a number with no row on screen able to
    /// clear it (a message from someone who never became a friend).
    private func refreshNotificationCount(_ userId: UUID) async {
        async let requestsTask = (try? FriendsService.loadRequests(for: userId)) ?? []
        async let unreadTask = (try? MessagesService.loadUnreadCounts(for: userId)) ?? [:]
        let (requests, unread) = await (requestsTask, unreadTask)
        let friendIds = Set(friends.map(\.id))
        let unreadFromFriends = unread
            .filter { friendIds.contains($0.key) }
            .values
            .reduce(0, +)
        notificationCount = requests.count + unreadFromFriends
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

/// A friend's map pin. All the drawing lives in `MapAvatarPin` so your own
/// pin and a friend's are literally the same view; this just unpacks a
/// `Friend` into it.
struct FriendPin: View {
    let friend: Friend

    private var staleLabel: String? {
        guard !friend.isLive, let updated = friend.location?.updatedAt else { return nil }
        return updated.relativeLabel
    }

    var body: some View {
        MapAvatarPin(
            profile: friend.profile,
            isLive: friend.isLive,
            speed: friend.isLive ? friend.location?.speed : nil,
            staleLabel: staleLabel
        )
    }
}

/// Port of `.avatar-photo`: a rounded square by default (a "squircle", not a
/// circle — Zenly's own signature avatar treatment), filled with the
/// profile's own `avatar_color`, with an explicit `.circle` escape hatch for
/// the map pin and story rings, the two places the web app itself switches
/// shapes.
struct AvatarView: View {
    enum AvatarShape { case squircle, circle }

    let profile: Profile
    var size: CGFloat = 44
    var shape: AvatarShape = .squircle
    var borderWidth: CGFloat?
    /// `<Avatar showStatus />` — the small status-emoji disc (`.avatar-photo i`).
    var showStatus = false
    /// Bottom-right by default, matching `.avatar-photo i`. The profile
    /// avatar in Me flips it to the top, exactly like the web app's
    /// `.profile-avatar i { top: -7px; bottom: auto }` — otherwise the
    /// "Change avatar" pill hanging off the bottom edge collides with it.
    var statusCorner: Alignment = .bottomTrailing

    private var stroke: CGFloat { borderWidth ?? max(2, (size * 0.065).rounded()) }
    /// `.avatar-photo { --avatar-color: var(--coral) }` — the per-profile
    /// colour, falling back to coral exactly like the CSS custom property.
    private var tint: Color { Color(hexString: profile.avatarColor) ?? Theme.coral }

    var body: some View {
        ZStack {
            fillShape.fill(tint)
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
        .clipShape(fillShape)
        .overlay(fillShape.stroke(.white, lineWidth: stroke))
        .shadow(color: Color(hex: 0x35255B).opacity(0.16), radius: 6, y: 5)
        .overlay(alignment: statusCorner) {
            if showStatus, let emoji = profile.statusEmoji {
                Text(emoji)
                    .font(.system(size: size * 0.24))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: Color(hex: 0x2A1C48).opacity(0.18), radius: 3, y: 2)
                    .offset(x: size * 0.15, y: statusCorner == .topTrailing ? -size * 0.11 : size * 0.11)
            }
        }
    }

    private var fillShape: AnyShape {
        switch shape {
        case .squircle: AnyShape(RoundedRectangle(cornerRadius: Theme.avatarRadius(for: size), style: .continuous))
        case .circle: AnyShape(Circle())
        }
    }

    private var initial: some View {
        Text(profile.displayName.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .black, design: .rounded))
            .foregroundStyle(.white)
    }
}
