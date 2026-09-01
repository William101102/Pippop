import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity + Dynamic Island for an in-progress bump.
///
/// This is the payoff for going native: while you are walking toward a friend
/// you are looking *up*, not at the app. The distance lives in the Dynamic
/// Island and keeps counting down, and the whole thing disappears the moment
/// you meet. There is no web equivalent of this surface at all.
struct BumpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BumpActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color(hex: 0x1B1430))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    avatarBubble(context.attributes.friendName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.distanceText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(context.state.phase == .met ? "Met 🎉" : "away")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.friendName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    proximityBar(context.state)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .met
                      ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color(hex: 0xFF6847))
            } compactTrailing: {
                Text(compactDistance(context.state))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color(hex: 0xFF6847))
            }
            .keylineTint(Color(hex: 0xFF3F8E))
        }
    }

    // MARK: - Lock screen / banner

    private func lockScreen(_ context: ActivityViewContext<BumpActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            avatarBubble(context.attributes.friendName)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.friendName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(context.state.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                proximityBar(context.state)
            }

            Spacer(minLength: 0)

            if context.state.phase == .met {
                Text("🎉").font(.system(size: 30))
            } else {
                ringGauge(context.state)
            }
        }
        .padding(16)
    }

    // MARK: - Pieces

    private func avatarBubble(_ name: String) -> some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 40, height: 40)
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private func proximityBar(_ state: BumpActivityAttributes.ContentState) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(6, geo.size.width * state.proximity))
            }
        }
        .frame(height: 6)
    }

    private func ringGauge(_ state: BumpActivityAttributes.ContentState) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: state.proximity)
                .stroke(Color(hex: 0xFF3F8E), style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let bearing = state.bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.radians(bearing))
            }
        }
        .frame(width: 42, height: 42)
    }

    /// The compact trailing slot is only a few points wide — no decimals, no unit
    /// where it can be inferred.
    private func compactDistance(_ state: BumpActivityAttributes.ContentState) -> String {
        guard let distance = state.distance else { return "—" }
        if state.phase == .met { return "✓" }
        return distance < 1
            ? "\(Int(distance * 100))cm"
            : String(format: "%.0fm", distance)
    }
}
