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

                if friend.streakDays > 0 {
                    Label("\(friend.streakDays)-day streak", systemImage: "flame.fill")
                        .font(Theme.Font.body(12, weight: .heavy))
                        .foregroundStyle(Theme.coral)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.coral.opacity(0.12), in: Capsule())
                }

                if let milestone {
                    Label("\(milestone)-day streak!", systemImage: "sparkles")
                        .font(Theme.Font.body(12, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x8A5A00))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            LinearGradient(colors: [Color(hex: 0xFFE08A), Color(hex: 0xFF9F5A)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .transition(.scale.combined(with: .opacity))
                }

                if let distance = distanceText {
                    HStack(spacing: 8) {
                        Image(systemName: "location.north.line.fill")
                        Text(distance).font(Theme.Font.body(15, weight: .bold))
                        Text(friend.isLive ? "Live" : "Last seen")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: 0xF4F0F6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var distanceText: String? {
        guard
            let mine = location.current,
            let theirs = friend.location
        else { return nil }
        let metres = CLLocation(latitude: mine.lat, longitude: mine.lng)
            .distance(from: CLLocation(latitude: theirs.lat, longitude: theirs.lng))
        return metres < 1000
            ? String(format: "%.0f m", metres)
            : String(format: "%.1f km", metres / 1000)
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
