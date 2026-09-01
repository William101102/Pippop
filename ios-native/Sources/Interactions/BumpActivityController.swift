import ActivityKit
import Foundation

/// Owns the bump Live Activity's lifecycle.
///
/// ## Why the throttling matters
/// `NISession` reports several times a second. ActivityKit is **not** built for
/// that: the system budgets Live Activity updates and will start dropping (and
/// eventually throttling) an activity that pushes too often. So updates are
/// rate-limited to `minInterval`, and skipped entirely when the distance has
/// not moved by `minDelta`. Phase changes always go through immediately, since
/// those are the moments the user actually cares about.
@MainActor
final class BumpActivityController {
    private var activity: Activity<BumpActivityAttributes>?
    private var lastPushed: Date = .distantPast
    private var lastDistance: Double?

    private let minInterval: TimeInterval = 1.0
    private let minDelta: Double = 0.25 // metres

    static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(friendName: String) {
        guard Self.isAvailable, activity == nil else { return }
        let state = BumpActivityAttributes.ContentState(phase: .searching, distance: nil, bearing: nil)
        do {
            activity = try Activity.request(
                attributes: BumpActivityAttributes(friendName: friendName),
                content: .init(state: state, staleDate: Date().addingTimeInterval(5 * 60)),
                pushType: nil
            )
            lastPushed = .now
        } catch {
            activity = nil
        }
    }

    func update(phase: BumpActivityAttributes.ContentState.Phase, distance: Double?, bearing: Double?) {
        guard let activity else { return }

        let phaseChanged = activity.content.state.phase != phase
        let movedEnough: Bool = {
            guard let distance, let lastDistance else { return distance != nil }
            return abs(distance - lastDistance) >= minDelta
        }()
        let dueForRefresh = Date().timeIntervalSince(lastPushed) >= minInterval

        guard phaseChanged || (movedEnough && dueForRefresh) else { return }

        lastPushed = .now
        lastDistance = distance

        let state = BumpActivityAttributes.ContentState(
            phase: phase, distance: distance, bearing: bearing
        )
        Task {
            await activity.update(
                .init(state: state, staleDate: Date().addingTimeInterval(5 * 60))
            )
        }
    }

    /// `met` lingers briefly so the celebration is visible; a cancel dismisses
    /// immediately rather than leaving a dead activity on the Lock Screen.
    func finish(met: Bool) {
        guard let activity else { return }
        self.activity = nil
        let state = BumpActivityAttributes.ContentState(
            phase: met ? .met : .searching,
            distance: met ? 0 : nil,
            bearing: nil
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: met ? .after(.now.addingTimeInterval(6)) : .immediate
            )
        }
    }
}
