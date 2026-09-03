import CoreLocation
import SwiftUI

/// The friend sheet — distance, streak, and the throw grid.
///
/// Presented as a real sheet with detents, so the status-bar overlap problem
/// the web version had to solve with `max-height` math simply cannot occur:
/// UIKit owns the safe area.
struct PersonCard: View {
    let friend: Friend
    let onThrow: (Throwable, Double) -> Void

    @Environment(LocationService.self) private var location
    @State private var milestone: Int?
    @State private var milestoneHideTask: Task<Void, Never>?

    /// Escalating milestones, mirroring the web app's own `STREAK_MILESTONES`
    /// — big enough gaps that crossing one actually feels like an event.
    private static let streakMilestones = [3, 7, 14, 30, 50, 100, 200, 365]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AvatarView(profile: friend.profile, size: 86)
                    .padding(.top, 18)

                Text(friend.displayName)
                    .font(Theme.Font.display(28))
                    .foregroundStyle(Theme.ink)

                Text("@\(friend.profile.username)")
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)

                StreakBadge(info: friend.streak)

                if let milestone {
                    Label("\(milestone)-day streak!", systemImage: "sparkles")
                        .font(Theme.Font.body(12, weight: .heavy))
                        .foregroundStyle(Theme.warnInk)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.streakMilestoneGradient, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }

                if let compass = compassInfo {
                    PersonCompassCard(distanceLabel: compass.distance, directionLabel: compass.direction, isLive: friend.isLive, headingDegrees: compass.heading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("THROW SOMETHING")
                        .font(Theme.Font.body(10, weight: .heavy))
                        .kerning(1.3)
                        .foregroundStyle(Theme.pink)

                    Text("Hold to charge, let go to throw")
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 16) {
                        ForEach(Throwable.all) { throwable in
                            ThrowButton(throwable: throwable, onThrow: onThrow)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: milestone)
        }
        .background(Theme.ground)
        .task(id: friend.streakDays) { checkMilestone() }
        .onDisappear { milestoneHideTask?.cancel() }
    }

    /// Distance, 16-point compass direction, and true bearing to the friend
    /// — port of the web app's `fmtDist`/`compassLabel`/`bearingDeg`.
    private var compassInfo: (distance: String, direction: String, heading: Double)? {
        guard
            let mine = location.current,
            let theirs = friend.location
        else { return nil }
        let from = mine.coordinate
        let to = theirs.coordinate
        let metres = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        let distance = metres < 1000
            ? String(format: "%.0f m", metres)
            : String(format: "%.1f km", metres / 1000)
        let heading = Self.bearingDegrees(from: from, to: to)
        return (distance, Self.compassLabel(heading), heading)
    }

    private static func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func compassLabel(_ heading: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading / 45).rounded()) % 8
        return points[index]
    }

    /// Fires once per device the first time this friend's streak is seen
    /// crossing a milestone — a purely client-side "did you notice" nudge,
    /// no schema needed. Port of the web app's `useEffect` in `PersonCard`,
    /// using `UserDefaults` in place of `localStorage`.
    private func checkMilestone() {
        let key = "pinpop-streak-seen-\(friend.id.uuidString)"
        let defaults = UserDefaults.standard
        let seen = defaults.integer(forKey: key)
        let current = friend.streakDays

        // Scan high-to-low so a friend already on a long streak doesn't
        // falsely celebrate "3-day streak!" the first time their card opens.
        if let crossed = Self.streakMilestones.reversed().first(where: { current >= $0 && seen < $0 }) {
            Haptics.shared.play(.success)
            milestone = crossed
            defaults.set(current, forKey: key)
            milestoneHideTask?.cancel()
            milestoneHideTask = Task {
                try? await Task.sleep(for: .seconds(2.8))
                if !Task.isCancelled { milestone = nil }
            }
        } else if current != seen {
            defaults.set(current, forKey: key)
        }
    }
}

/// Port of `.person-compass`/`.compass-ring` — a small heading dial plus the
/// distance and live/last-seen state, replacing a plain distance pill.
private struct PersonCompassCard: View {
    let distanceLabel: String
    let directionLabel: String
    let isLive: Bool
    let headingDegrees: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Theme.adaptive(light: 0xD9D0EA, dark: 0x453B5C), lineWidth: 2)
                    .background(Circle().fill(Theme.surface))
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.coral)
                    .offset(y: -10)
                    .rotationEffect(.degrees(headingDegrees))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(distanceLabel)
                    .font(Theme.Font.display(18))
                    .foregroundStyle(Theme.ink)
                Text("\(directionLabel) · \(isLive ? "Live" : "Last seen")")
                    .font(Theme.Font.body(11, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Theme.adaptive(light: 0xF4F0FF, dark: 0x272040), Theme.warnSoft], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

/// Port of `.streak-badge` and its tier/at-risk/repairing/can-repair color
/// variants — see `StreakInfo` for the underlying math.
struct StreakBadge: View {
    let info: StreakInfo
    @State private var pulse = false

    var body: some View {
        Group {
            if info.repairing {
                text("Repairing streak — \(info.repairDaysLeft) more day\(info.repairDaysLeft == 1 ? "" : "s") in a row restores it to \(info.repairTarget)", icon: "🩹")
                    .foregroundStyle(Theme.infoInk)
                    .background(
                        LinearGradient(colors: [Theme.adaptive(light: 0xEAF6FF, dark: 0x1B3448), Theme.adaptive(light: 0xDFF0FF, dark: 0x16293A)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
            } else if info.canRepair {
                text("Missed yesterday — interact today to start repairing it back to \(info.repairTarget)", icon: "💔")
                    .foregroundStyle(Theme.dangerInk)
                    .background(Theme.dangerSoft, in: Capsule())
                    .opacity(pulse ? 0.55 : 1)
                    .onAppear { startPulse() }
            } else if info.days > 0 {
                text("\(info.days)-day streak", icon: info.icon)
                    .foregroundStyle(Theme.warnInk)
                    .background(
                        info.tier == .blaze || info.tier == .legend ? AnyShapeStyle(Theme.streakHotGradient) : AnyShapeStyle(Theme.streakBaseGradient),
                        in: Capsule()
                    )
                    .opacity(info.atRisk && pulse ? 0.55 : 1)
                    .onAppear { if info.atRisk { startPulse() } }
            }
        }
    }

    private func text(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Text(icon)
            Text(label)
        }
        .font(Theme.Font.body(11, weight: .heavy))
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
