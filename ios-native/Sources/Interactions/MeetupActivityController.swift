import ActivityKit
import CoreLocation
import Foundation

/// Starts, feeds and ends the "Heading to <friend>" Live Activity.
///
/// ## Update budget
///
/// ActivityKit throttles an app that pushes constantly, and the island is not
/// a speedometer — so updates are gated the same way location uploads are:
/// at most one every `minInterval`, and only when the distance has actually
/// moved by `minDelta`. `NSSupportsLiveActivitiesFrequentUpdates` is set in
/// project.yml, but that raises the ceiling, it doesn't remove it.
///
/// ## What keeps it alive
///
/// There's no push entitlement on a personal team (`aps-environment` is
/// commented out in project.yml), so every update has to come from this
/// process. With Always location that process is usually running — but if the
/// user force-quits the app, the island freezes at its last value until they
/// open it again. Nothing can be done about that without push.
@MainActor
final class MeetupActivityController {
    static let shared = MeetupActivityController()

    private var activity: Activity<MeetupActivityAttributes>?
    private var lastPushedAt: Date?
    private var lastPushedDistance: Double?

    /// Who we're currently heading to, so the map can tell whether to feed
    /// updates and the UI can show "stop".
    private(set) var friendId: UUID?

    private static let minInterval: TimeInterval = 20
    private static let minDelta: CLLocationDistance = 20
    /// Close enough to be looking at each other rather than at a phone.
    private static let arrivalDistance: CLLocationDistance = 25

    private init() {}

    var isRunning: Bool { activity != nil }

    func start(friend: Friend, from mine: Fix) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()

        let distance = Self.distance(from: mine, to: friend)
        let attributes = MeetupActivityAttributes(
            friendName: friend.displayName,
            friendInitial: String(friend.displayName.prefix(1)).uppercased(),
            avatarColorHex: friend.profile.avatarColor,
            // A floor, so a trip that starts from across the room still has a
            // progress bar that can move rather than one pinned at 100%.
            startDistance: max(distance ?? 0, 50),
            friendURL: URL(string: "pinpop://friend/\(friend.id.uuidString)")
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state(for: friend, from: mine), staleDate: nil),
                pushType: nil
            )
            friendId = friend.id
            lastPushedAt = .now
            lastPushedDistance = distance
        } catch {
            // Activities can be off system-wide, or already at the limit.
            activity = nil
            friendId = nil
        }
    }

    /// Feed a fresh position. Cheap no-op when nothing is running, when the
    /// update is for someone else, or when too little has changed to be worth
    /// spending budget on.
    func update(friend: Friend, from mine: Fix) async {
        guard let activity, friend.id == friendId else { return }
        let distance = Self.distance(from: mine, to: friend)
        let arrived = (distance ?? .greatestFiniteMagnitude) <= Self.arrivalDistance

        if !arrived, !shouldPush(distance: distance) { return }
        lastPushedAt = .now
        lastPushedDistance = distance

        var next = state(for: friend, from: mine)
        next.hasArrived = arrived
        await activity.update(ActivityContent(state: next, staleDate: nil))

        if arrived {
            // Let the arrival actually land on screen before clearing it.
            await finish(after: 90)
        }
    }

    /// Ends immediately — the user tapped stop, or opened the friend's card
    /// and the trip is over.
    func end() {
        guard let activity else { return }
        self.activity = nil
        friendId = nil
        lastPushedAt = nil
        lastPushedDistance = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func finish(after seconds: TimeInterval) async {
        guard let activity else { return }
        self.activity = nil
        friendId = nil
        await activity.end(nil, dismissalPolicy: .after(.now.addingTimeInterval(seconds)))
    }

    private func shouldPush(distance: Double?) -> Bool {
        if let last = lastPushedAt, Date.now.timeIntervalSince(last) < Self.minInterval { return false }
        guard let distance, let previous = lastPushedDistance else { return true }
        return abs(distance - previous) >= Self.minDelta
    }

    private func state(for friend: Friend, from mine: Fix) -> MeetupActivityAttributes.ContentState {
        MeetupActivityAttributes.ContentState(
            distance: Self.distance(from: mine, to: friend),
            bearing: Self.bearing(from: mine, to: friend),
            statusEmoji: friend.profile.statusEmoji,
            isStale: !friend.isLive,
            lastSeen: friend.location?.updatedAt ?? .now,
            hasArrived: false
        )
    }

    private static func distance(from mine: Fix, to friend: Friend) -> Double? {
        guard let theirs = friend.location else { return nil }
        return CLLocation(latitude: mine.lat, longitude: mine.lng)
            .distance(from: CLLocation(latitude: theirs.lat, longitude: theirs.lng))
    }

    /// Degrees clockwise from north — same maths as `PersonCard`'s compass,
    /// which is what the island's arrow is a miniature of.
    private static func bearing(from mine: Fix, to friend: Friend) -> Double? {
        guard let theirs = friend.location else { return nil }
        let lat1 = mine.lat * .pi / 180
        let lat2 = theirs.lat * .pi / 180
        let dLon = (theirs.lng - mine.lng) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
