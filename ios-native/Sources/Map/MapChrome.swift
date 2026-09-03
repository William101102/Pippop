import CoreLocation
import SwiftUI

/// Formatting helpers ported from `src/lib/format.ts`, so the same numbers
/// read the same way on both clients.
enum Fmt {
    /// `fmtDist` — metres under a kilometre, one decimal above it.
    static func distance(_ metres: CLLocationDistance) -> String {
        metres < 1000
            ? String(format: "%.0f m", metres)
            : String(format: "%.1f km", metres / 1000)
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        distance(CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)))
    }

    /// `fmtSpeed` — m/s to km/h. Nil below walking pace, which is where the
    /// web app stops drawing the speed pill under a pin.
    static func speedKmh(_ metresPerSecond: Double?) -> String? {
        guard let metresPerSecond, metresPerSecond > 0 else { return nil }
        let kmh = metresPerSecond * 3.6
        guard kmh >= 2 else { return nil }
        return String(format: "%.0f km/h", kmh)
    }

    /// The same speed split into the two lines Zenly's badge stacks — a big
    /// number over a small unit. Follows the phone's own measurement system,
    /// so a US device reads "18 / MPH" and a metric one "29 / KM/H".
    static func speedBadge(_ metresPerSecond: Double?) -> (value: String, unit: String)? {
        guard let metresPerSecond, metresPerSecond > 0 else { return nil }
        let metric = Locale.current.measurementSystem != .us
        let converted = metresPerSecond * (metric ? 3.6 : 2.236_936_3)
        guard converted >= 2 else { return nil }
        return (String(format: "%.0f", converted), metric ? "KM/H" : "MPH")
    }
}

/// The soft teardrop under a map pin, so the circle actually points at the
/// spot it marks. Real Zenly keeps this tail; the web rewrite dropped it for
/// a plain circle, and a plain circle floating over a street is noticeably
/// vaguer about *where* someone is.
struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.55)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

/// A person on the map — you or a friend, same treatment either way, which is
/// how both Zenly and the web app do it.
///
/// Photo fills the circle, a thick ring around it carries the live/away state
/// (green pulses while sharing, grey when the fix has gone stale), the status
/// emoji sits top-right, and a speed badge overlaps the bottom-left while the
/// person is actually moving.
struct MapAvatarPin: View {
    let profile: Profile
    var isLive: Bool = true
    /// Metres per second, straight off the fix.
    var speed: Double?
    /// "3h ago" — shown instead of a speed once the fix is stale.
    var staleLabel: String?

    @State private var pulse = false

    private static let live = Color(hex: 0x25CC92)
    private static let away = Color(hex: 0xC4BCD0)
    private var ringColor: Color { isLive ? Self.live : Self.away }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    // The pulse ring, behind everything — `.person-pin.live::after`.
                    Circle()
                        .stroke(ringColor, lineWidth: 3)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isLive && pulse ? 1.5 : 1)
                        .opacity(isLive && pulse ? 0 : (isLive ? 0.9 : 0))

                    Circle()
                        .fill(ringColor)
                        .frame(width: 60, height: 60)

                    AvatarView(profile: profile, size: 52, shape: .circle, borderWidth: 0)

                    if let emoji = profile.statusEmoji {
                        Text(emoji)
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: Color(hex: 0x291948).opacity(0.2), radius: 4, y: 3)
                            .offset(x: 26, y: -26)
                    }
                }
                .frame(width: 60, height: 60)

                if let badge = Fmt.speedBadge(speed) {
                    VStack(spacing: -2) {
                        Text(badge.value)
                            .font(Theme.Font.display(15))
                        Text(badge.unit)
                            .font(Theme.Font.body(7, weight: .heavy))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Self.live.opacity(0.95)))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: -16, y: 6)
                } else if let staleLabel {
                    Text(staleLabel)
                        .font(Theme.Font.body(9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(hex: 0x261A40).opacity(0.82), in: Capsule())
                        .fixedSize()
                        .offset(x: -10, y: 8)
                }
            }

            PinTail()
                .fill(ringColor)
                .frame(width: 16, height: 11)
                .offset(y: -2)
        }
        .grayscale(isLive ? 0 : 0.35)
        .opacity(isLive ? 1 : 0.88)
        .shadow(color: Theme.ink.opacity(isLive ? 0.26 : 0.18), radius: 9, y: 7)
        .onAppear {
            guard isLive else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// A "you slept here" pin — a label bubble over a small badge, the same
/// two-tier treatment real Zenly uses for "Night place"/"Home"/"Work" pins.
/// Diamond + moon while the streak is still building, a plain rounded square
/// + house once `PlacesService.homeStreakNights` nights in a row promote it
/// to "Home" — the shape change alone reads as "this one's confirmed"
/// without needing a third color.
struct NightPlacePin: View {
    let place: SignificantPlace

    var body: some View {
        VStack(spacing: 5) {
            Text(place.isHome ? "HOME" : "NIGHT PLACE")
                .font(Theme.Font.body(9, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .shadow(color: Theme.ink.opacity(0.14), radius: 6, y: 3)

            badge
        }
    }

    private var badge: some View {
        ZStack {
            if place.isHome {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.coral, Color(hex: 0xE8455B)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.violet, Color(hex: 0x5B3FA0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(45))
            }
            Image(systemName: place.isHome ? "house.fill" : "moon.stars.fill")
                .font(.system(size: place.isHome ? 15 : 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(.white, lineWidth: 2).opacity(place.isHome ? 1 : 0))
        .shadow(color: (place.isHome ? Theme.coral : Theme.violet).opacity(0.35), radius: 6, y: 4)
    }
}

/// The closest-friend pill under the top bar — port of `.map-mood`.
struct MapMoodPill: View {
    let friend: Friend
    let distanceText: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let emoji = friend.profile.statusEmoji {
                    Text(emoji).font(Theme.Font.body(12, weight: .heavy))
                }
                Text(friend.displayName)
                    .font(Theme.Font.display(13))
                    .foregroundStyle(Theme.ink)
                Text(distanceText)
                    .font(Theme.Font.body(12, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if let updated = friend.location?.updatedAt {
                    Text(updated.relativeLabel)
                        .font(Theme.Font.body(10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .floatingCard(radius: 99, style: .glass)
        }
        .pressable()
    }
}

/// One of the round tools stacked down the right edge — port of
/// `.map-tools button` (45×45 glass circle).
struct MapToolButton: View {
    let symbol: String
    var isActive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? .white : Theme.ink)
                .frame(width: 43, height: 43)
                .background {
                    if isActive {
                        Circle().fill(Theme.violet)
                    }
                }
                .floatingCard(radius: 22, style: .glass)
        }
        .pressable()
    }
}

/// The friend carousel that sits just above the dock — port of `.map-peek`
/// wrapping `.friend-rail`. This is the piece of Zenly's home screen the
/// native build was missing entirely: you first, then every friend, then an
/// "add" tile, each tap re-centring the map on that person.
struct FriendRailView: View {
    let me: Profile
    let friends: [Friend]
    let selectedId: UUID?
    var onSelectMe: () -> Void
    var onSelect: (Friend) -> Void
    var onAdd: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                item(profile: me, label: "You", isMine: true, isActive: selectedId == me.id, action: onSelectMe)
                ForEach(friends) { friend in
                    item(
                        profile: friend.profile,
                        label: friend.displayName,
                        isMine: false,
                        isActive: selectedId == friend.id
                    ) { onSelect(friend) }
                }
                addItem
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
    }

    private func item(profile: Profile, label: String, isMine: Bool, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AvatarView(profile: profile, size: 44, showStatus: true)
                    .padding(3)
                    .overlay(
                        // Only the focused person gets a ring. The web app
                        // also draws a permanent coral ring around "You", but
                        // with the "You" label right underneath it that ring
                        // is pure redundancy — and at native's ring weight it
                        // read as a heavy orange box around the avatar.
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isActive ? Theme.violet : .clear, lineWidth: 2)
                    )
                    .offset(y: isActive ? -2 : 0)
                Text(label)
                    .font(Theme.Font.body(10, weight: .heavy))
                    .foregroundStyle(isActive ? Theme.violet : Theme.ink)
                    .lineLimit(1)
                    .frame(width: 58)
                    // `--rail-label-halo`: these labels sit on raw map tiles,
                    // not on a surface, so they carry their own white halo.
                    .shadow(color: .white, radius: 3)
                    .shadow(color: .white.opacity(0.9), radius: 6)
            }
            .frame(width: 58)
        }
        .pressable(scale: 0.95)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private var addItem: some View {
        Button(action: onAdd) {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 50, height: 50)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.adaptive(light: 0xD8D0E0, dark: 0x4A4260), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    )
                Text("Add")
                    .font(Theme.Font.body(10, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .shadow(color: .white, radius: 3)
            }
            .frame(width: 58)
        }
        .pressable(scale: 0.95)
    }
}
