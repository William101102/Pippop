import CoreMotion
import SwiftUI
import UIKit

// MARK: - Shake

/// UIKit delivers shake through the responder chain, which SwiftUI does not
/// expose — so we widen `UIWindow` once and republish it as a notification.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("PinpopDeviceDidShake")
}

extension View {
    /// Shake-to-wave. Debounced so one physical shake fires once.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeHandler(action: action))
    }
}

private struct ShakeHandler: ViewModifier {
    let action: () -> Void
    @State private var lastFired: Date = .distantPast

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            guard Date().timeIntervalSince(lastFired) > 1.2 else { return }
            lastFired = Date()
            Haptics.shared.play(.success)
            action()
        }
    }
}

// MARK: - Knock (tap the back of the phone)

/// Detects a double or triple knock on the back of the device.
///
/// ## Why this exists alongside `BackTapIntent`
/// iOS's real **Back Tap** (Settings → Accessibility → Touch → Back Tap) can
/// only be bound to system actions and Shortcuts — a third-party app cannot
/// subscribe to it directly. The supported route is to expose an App Intent
/// (see `BackTapIntent.swift`) that the user assigns to Back Tap themselves.
///
/// This detector is the in-app alternative: while a screen is open we watch
/// `CMMotionManager` for the sharp, short z-axis spikes a knock produces. It
/// only runs while a view asks for it, because polling the accelerometer at
/// 50 Hz is not free.
@MainActor
@Observable
final class KnockDetector {
    private let motion = CMMotionManager()
    private var spikes: [Date] = []
    private var onKnock: ((Int) -> Void)?

    /// Tuned for a deliberate knock rather than a pocket bump. Raise if you see
    /// false positives while walking.
    private let spikeThreshold = 2.2      // g, on user acceleration
    private let clusterWindow: TimeInterval = 0.6
    private let refractory: TimeInterval = 0.08
    private var lastSpike: Date = .distantPast

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start(onKnock: @escaping (Int) -> Void) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        self.onKnock = onKnock
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.consume(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        spikes.removeAll()
        onKnock = nil
    }

    private func consume(_ data: CMDeviceMotion) {
        // A knock on the back shows up mostly on z, as a brief spike well above
        // the gentle accelerations of ordinary handling.
        let z = abs(data.userAcceleration.z)
        let now = Date()
        guard z >= spikeThreshold, now.timeIntervalSince(lastSpike) > refractory else { return }
        lastSpike = now

        spikes.append(now)
        spikes = spikes.filter { now.timeIntervalSince($0) <= clusterWindow }

        // Wait out the window, then report the cluster size so double and
        // triple knocks can mean different things.
        let count = spikes.count
        guard count >= 2 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(clusterWindow))
            guard self.spikes.count == count else { return } // a later spike grew it
            self.spikes.removeAll()
            Haptics.shared.play(.tap)
            self.onKnock?(count)
        }
    }
}
