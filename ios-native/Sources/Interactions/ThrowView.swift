import CoreHaptics
import SwiftUI

struct Throwable: Identifiable, Hashable {
    let emoji: String
    let label: String
    var id: String { emoji }

    static let all: [Throwable] = [
        .init(emoji: "🎂", label: "Cake"), .init(emoji: "🌹", label: "Rose"),
        .init(emoji: "🍕", label: "Pizza"), .init(emoji: "❤️", label: "Love"),
        .init(emoji: "💦", label: "Splash"), .init(emoji: "⚡️", label: "Zap"),
        .init(emoji: "🎉", label: "Cheers"), .init(emoji: "☕️", label: "Coffee"),
        .init(emoji: "🏀", label: "Ball"), .init(emoji: "🔥", label: "Fire"),
        .init(emoji: "🍺", label: "Beer"), .init(emoji: "🌮", label: "Taco"),
        .init(emoji: "👻", label: "Boo"), .init(emoji: "🪩", label: "Party"),
    ]
}

/// Press-and-hold to charge, release to throw.
///
/// The charge drives three things at once — scale, a filling ring, and a Core
/// Haptics intensity ramp — so the build-up is felt as well as seen. Power is
/// carried into the flight animation, so a long charge visibly throws harder.
/// This is the interaction the web version cannot reproduce: `navigator.vibrate`
/// is unavailable on iOS Safari, and a WebView has no haptic ramp at all.
struct ThrowButton: View {
    let throwable: Throwable
    let onThrow: (Throwable, Double) -> Void

    private let maxCharge: TimeInterval = 1.4

    @State private var isCharging = false
    @State private var power: Double = 0
    @State private var chargeStart: Date?
    @State private var player: CHHapticAdvancedPatternPlayer?
    @State private var ticker: Timer?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Theme.ink.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: power)
                    .stroke(Theme.brandGradient, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(throwable.emoji)
                    .font(.system(size: 24))
                    .scaleEffect(1 + power * 0.35)
            }
            .frame(width: 54, height: 54)

            Text(throwable.label)
                .font(Theme.Font.body(9, weight: .heavy))
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.01)
                .onEnded { _ in beginCharge() }
                .sequenced(before: DragGesture(minimumDistance: 0).onEnded { _ in release() })
        )
        .onDisappear { cancelCharge() }
        .animation(.easeOut(duration: 0.12), value: power)
    }

    private func beginCharge() {
        guard !isCharging else { return }
        isCharging = true
        chargeStart = Date()
        player = Haptics.shared.startCharge(duration: maxCharge)

        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { _ in
            Task { @MainActor in
                guard let start = chargeStart else { return }
                power = min(1, Date().timeIntervalSince(start) / maxCharge)
                if power >= 1 { stopHaptics() }
            }
        }
    }

    private func release() {
        guard isCharging else { return }
        let thrown = max(0.15, power)
        cancelCharge()
        Haptics.shared.play(.release)
        onThrow(throwable, thrown)
    }

    private func cancelCharge() {
        isCharging = false
        chargeStart = nil
        power = 0
        ticker?.invalidate(); ticker = nil
        stopHaptics()
    }

    private func stopHaptics() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }
}

/// The emoji arcing away after a throw. Power stretches the arc and shortens
/// the flight, so a full charge reads as a harder throw.
struct ThrowFlightView: View {
    let emoji: String
    let power: Double
    @State private var progress: Double = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: 44))
            .offset(
                x: progress * 150 * (0.6 + power),
                y: -sin(progress * .pi) * (110 + power * 90) + progress * 40
            )
            .rotationEffect(.degrees(progress * 360 * (0.5 + power)))
            .opacity(1 - progress * progress)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9 - power * 0.25)) { progress = 1 }
            }
            .allowsHitTesting(false)
    }
}
