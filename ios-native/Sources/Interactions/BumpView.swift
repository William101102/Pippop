import SwiftUI
import simd

/// The "hold your phones together" screen.
///
/// Shows live distance and, when the U1 chip can resolve it, an arrow pointing
/// at the other phone. Both people need this screen open — that mutual, physical
/// ritual is the point, and it is what makes the meeting trustworthy enough to
/// count toward a streak.
struct BumpView: View {
    @State private var bump = BumpService()
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    var onMet: (BumpService.Met) -> Void

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 26) {
                header

                switch bump.phase {
                case .unsupported:
                    unsupported
                case .idle, .searching:
                    radar(distance: nil, direction: nil)
                    Text("Looking for a friend nearby…")
                        .font(Theme.Font.body(13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                case let .tracking(name, distance, direction):
                    radar(distance: distance, direction: direction)
                    VStack(spacing: 4) {
                        Text(name).font(Theme.Font.display(22)).foregroundStyle(Theme.ink)
                        Text(distanceLabel(distance))
                            .font(Theme.Font.body(15, weight: .bold))
                            .foregroundStyle(Theme.violet)
                        Text("Move closer until your phones touch")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                case let .bumped(name):
                    met(name)
                case let .failed(message):
                    Text(message)
                        .font(Theme.Font.body(12, weight: .medium))
                        .foregroundStyle(Theme.coral)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .padding(.top, 30)
        }
        // `fullScreenCover` (how MapScreen presents this) gives up the sheet's
        // swipe-down-to-dismiss for free, and this screen had no on-screen way
        // out either — you were stuck here until a bump actually happened. A
        // close button, always available regardless of phase, fixes that.
        // `.safeAreaInset` rather than a ZStack/overlay sibling keeps it clear
        // of the Dynamic Island and guarantees it's actually tappable there —
        // see the comment in MapScreen.swift for why a plain sibling of a
        // view that calls `.ignoresSafeArea()` can't be trusted to stay in a
        // touchable safe area.
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .floatingCard(radius: 18)
                }
                .pressable()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .onAppear {
            guard let me = auth.profile else { return }
            bump.start(userId: me.id, displayName: me.displayName) { met in
                onMet(met)
                // Attribute the meeting server-side so it can bump the streak.
                if let friendId = met.userId {
                    Task { try? await SocialService.recordBump(with: friendId) }
                }
            }
        }
        .onDisappear { bump.stop() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("BUMP TO MEET")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)
            Text("Say hi in person")
                .font(Theme.Font.display(28))
                .foregroundStyle(Theme.ink)
        }
    }

    private var unsupported: some View {
        VStack(spacing: 12) {
            Text("📡").font(.system(size: 44))
            Text("This iPhone can't do precise bumps")
                .font(Theme.Font.body(14, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Bump needs the ultra-wideband chip in iPhone 11 and later. You can still wave and throw things.")
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 40)
    }

    private func met(_ name: String) -> some View {
        VStack(spacing: 14) {
            Text("🎉").font(.system(size: 62))
            Text("You met \(name)!")
                .font(Theme.Font.display(26))
                .foregroundStyle(Theme.ink)
            Text("Your streak just went up.")
                .font(Theme.Font.body(13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Button("Done") { dismiss() }
                .font(Theme.Font.body(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .pressable()
        }
        .padding(.top, 30)
    }

    /// Concentric rings that tighten as the peer gets closer, with a heading
    /// arrow when UWB can resolve direction.
    private func radar(distance: Float?, direction: simd_float3?) -> some View {
        let proximity = distance.map { max(0, min(1, 1 - Double($0) / 6)) } ?? 0

        return ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(Theme.violet.opacity(0.16 + proximity * 0.2), lineWidth: 2)
                    .frame(width: 90 + CGFloat(ring) * 62)
                    .scaleEffect(1 - proximity * 0.16)
            }

            Circle()
                .fill(Theme.brandGradient)
                .frame(width: 62 + proximity * 26)
                .shadow(color: Theme.pink.opacity(0.4), radius: 20, y: 8)
                .overlay(Text("📍").font(.system(size: 26)))

            if let direction {
                // atan2 on the x/z plane gives the bearing to the peer while the
                // phone is held upright.
                let angle = Double(atan2(direction.x, -direction.z))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.violet)
                    .offset(y: -108)
                    .rotationEffect(.radians(angle))
                    .animation(.easeOut(duration: 0.2), value: direction)
            }
        }
        .frame(height: 240)
        .animation(.easeOut(duration: 0.25), value: proximity)
    }

    private func distanceLabel(_ distance: Float?) -> String {
        guard let distance else { return "Getting a fix…" }
        return distance < 1
            ? String(format: "%.0f cm away", distance * 100)
            : String(format: "%.1f m away", distance)
    }
}
