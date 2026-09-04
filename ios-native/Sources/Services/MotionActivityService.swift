import CoreMotion
import Foundation

/// What the phone thinks its owner is *doing* — walking, driving, sitting
/// still — as opposed to where they are.
///
/// This is the motion coprocessor's own classification (`CMMotionActivity`),
/// not something derived from GPS speed, and it's the right answer to "only
/// show a speed when they're really moving": a shake never reads as
/// `automotive`, and a phone on a desk reads `stationary` no matter what
/// noise the GPS is producing.
///
/// It's also nearly free — the M-series coprocessor records this whether or
/// not any app asks, which is why `queryActivityStarting(from:to:)` can hand
/// back roughly the last **seven days** of history even if the app never ran.
///
/// Permission is separate from location: "Motion & Fitness", covered by
/// `NSMotionUsageDescription` in project.yml. If it's refused, everything
/// here stays `.unknown` and callers fall back to the speed filtering in
/// `LocationService`.
@MainActor
@Observable
final class MotionActivityService {
    enum Mode: String, Sendable {
        case unknown, stationary, walking, running, cycling, driving

        var label: String {
            switch self {
            case .unknown: "Unknown"
            case .stationary: "Still"
            case .walking: "Walking"
            case .running: "Running"
            case .cycling: "Cycling"
            case .driving: "Driving"
            }
        }

        var symbol: String {
            switch self {
            case .unknown: "questionmark.circle"
            case .stationary: "figure.stand"
            case .walking: "figure.walk"
            case .running: "figure.run"
            case .cycling: "bicycle"
            case .driving: "car.fill"
            }
        }
    }

    private(set) var mode: Mode = .unknown
    private(set) var isAvailable = CMMotionActivityManager.isActivityAvailable()

    /// Whether a speed is worth showing at all. `.unknown` counts as moving
    /// on purpose — if Motion & Fitness was refused, this must not become a
    /// switch that silently hides every speed forever; `LocationService`'s
    /// own two-reading confirmation still applies underneath.
    var isMoving: Bool {
        switch mode {
        case .walking, .running, .cycling, .driving, .unknown: true
        case .stationary: false
        }
    }

    private let manager = CMMotionActivityManager()
    private var running = false

    func start() {
        guard isAvailable, !running else { return }
        running = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            // Low confidence is mostly the transition between two states;
            // holding the previous answer avoids the badge flickering.
            guard activity.confidence != .low else { return }
            self.mode = Self.mode(for: activity)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopActivityUpdates()
        mode = .unknown
    }

    /// Was this phone left alone for the whole window ending now?
    ///
    /// Answered from the coprocessor's **recorded history** rather than from
    /// live updates, which is the only reason sleep detection can work at
    /// all: the app is not running at 2 AM, but the phone was still writing
    /// this log, and roughly a week of it can be read back at any time.
    ///
    /// "Still" means no confident walking/running/cycling/automotive sample
    /// in the window. A phone on a nightstand qualifies; a phone being held,
    /// carried or typed on does not.
    static func hasBeenStill(since start: Date) async -> Bool {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .authorized
        else { return false }

        let manager = CMMotionActivityManager()
        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.queryActivityStarting(from: start, to: Date(), to: .main) { activities, _ in
                // The handler is documented as one-shot, but resuming a
                // continuation twice is a crash, so this refuses to.
                guard !resumed else { return }
                resumed = true
                guard let activities, !activities.isEmpty else {
                    // No samples at all means no evidence of stillness
                    // either — don't call that sleep.
                    continuation.resume(returning: false)
                    return
                }
                let moved = activities.contains { activity in
                    guard activity.confidence != .low else { return false }
                    return activity.walking || activity.running || activity.cycling || activity.automotive
                }
                continuation.resume(returning: !moved)
            }
        }
    }

    private static func mode(for activity: CMMotionActivity) -> Mode {
        // Order matters: iOS can flag more than one at a time (automotive and
        // stationary are both true at a red light, which should read as
        // driving, not as standing still).
        if activity.automotive { return .driving }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
