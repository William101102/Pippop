import CoreHaptics
import UIKit

/// Core Haptics, not just `UIImpactFeedbackGenerator`.
///
/// The difference matters for the throw: a charge needs a *ramp* — intensity
/// and sharpness rising over a second — which the canned feedback generators
/// cannot express. That texture is a large part of why the native build feels
/// different from the web one.
@MainActor
final class Haptics {
    static let shared = Haptics()

    enum Pattern {
        case tap
        case success
        case warning
        /// Rising rumble while the user holds to charge a throw.
        case charge(duration: TimeInterval)
        /// Sharp release at the end of a charge.
        case release
        /// Two quick knocks — the moment two phones meet.
        case bump
    }

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() { prepare() }

    private func prepare() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The system stops the engine when the app backgrounds or after an
            // audio-session interruption; restart rather than going silent.
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in try? self?.engine?.start() }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func play(_ pattern: Pattern) {
        guard supportsHaptics, let engine else {
            fallback(pattern)
            return
        }
        do {
            let haptic = try CHHapticPattern(events: events(for: pattern), parameters: [])
            let player = try engine.makePlayer(with: haptic)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(pattern)
        }
    }

    private func events(for pattern: Pattern) -> [CHHapticEvent] {
        func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity),
                    .init(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time
            )
        }

        switch pattern {
        case .tap:
            return [transient(0, intensity: 0.6, sharpness: 0.5)]
        case .success:
            return [
                transient(0, intensity: 0.7, sharpness: 0.4),
                transient(0.11, intensity: 1.0, sharpness: 0.7),
            ]
        case .warning:
            return [
                transient(0, intensity: 0.9, sharpness: 0.9),
                transient(0.13, intensity: 0.5, sharpness: 0.3),
            ]
        case .bump:
            return [
                transient(0, intensity: 1.0, sharpness: 1.0),
                transient(0.08, intensity: 0.85, sharpness: 0.6),
                transient(0.2, intensity: 0.6, sharpness: 0.3),
            ]
        case .release:
            return [transient(0, intensity: 1.0, sharpness: 0.9)]
        case let .charge(duration):
            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.25),
                    .init(parameterID: .hapticSharpness, value: 0.2),
                ],
                relativeTime: 0,
                duration: duration
            )
            return [continuous]
        }
    }

    /// Devices without the Taptic Engine (or when CoreHaptics fails) still get
    /// something, so the interaction never feels broken.
    private func fallback(_ pattern: Pattern) {
        switch pattern {
        case .tap, .charge:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .release, .bump:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    /// Ramps intensity/sharpness while a charge is held. Returns a handle the
    /// caller stops on release.
    func startCharge(duration: TimeInterval = 1.4) -> CHHapticAdvancedPatternPlayer? {
        guard supportsHaptics, let engine else { return nil }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.2),
                .init(parameterID: .hapticSharpness, value: 0.1),
            ],
            relativeTime: 0,
            duration: duration
        )
        let ramp = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.2),
                .init(relativeTime: duration, value: 1.0),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [ramp])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            return nil
        }
    }
}
