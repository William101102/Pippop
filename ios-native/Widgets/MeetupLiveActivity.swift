import ActivityKit
import SwiftUI
import WidgetKit

/// "Heading to Maya" in the Dynamic Island and on the Lock Screen.
///
/// The four presentations are not four designs — they're one idea at four
/// sizes, and each drops whatever no longer fits:
///
/// - **minimal** (sharing the island with another app): just the person.
/// - **compact**: the person, and how far.
/// - **expanded**: the person, how far, which way, and how much of the trip
///   is behind you.
/// - **lock screen**: the same as expanded, laid out wide.
struct MeetupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetupActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Brand.night.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        AvatarBubble(context: context, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.friendName)
                                .font(Brand.display(15))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(context.state.headline)
                                .font(Brand.text(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    DistanceStack(state: context.state, size: 26)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    // The arrow is the one thing the island can give you that
                    // a notification can't: glanceable direction, without
                    // unlocking anything.
                    BearingArrow(bearing: context.state.bearing, arrived: context.state.hasArrived)
                        .frame(height: 26)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        TripProgress(context: context)

                        if let url = context.attributes.friendURL, !context.state.hasArrived {
                            // A Link, not a Button(intent:). An in-place
                            // button would have to run app code — and the
                            // Supabase client isn't linked into this
                            // extension, deliberately. Opening straight to
                            // their card is one tap either way.
                            Link(destination: url) {
                                Text("Open \(context.attributes.friendName)")
                                    .font(Brand.text(12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(Brand.gradient, in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                AvatarBubble(context: context, size: 20)
            } compactTrailing: {
                Text(context.state.compactText)
                    .font(Brand.display(13))
                    .foregroundStyle(context.state.hasArrived ? Brand.live : .white)
                    .monospacedDigit()
            } minimal: {
                AvatarBubble(context: context, size: 20)
            }
            .widgetURL(context.attributes.friendURL)
            .keylineTint(context.state.hasArrived ? Brand.live : Brand.coral)
        }
    }
}

/// The person, as the app draws them when a photo isn't available: their
/// initial on their own avatar colour, ringed in live green.
private struct AvatarBubble: View {
    let context: ActivityViewContext<MeetupActivityAttributes>
    var size: CGFloat

    private var tint: Color {
        Color(hexString: context.attributes.avatarColorHex) ?? Brand.coral
    }

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text(context.attributes.friendInitial)
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            if let emoji = context.state.statusEmoji, size >= 30 {
                Text(emoji)
                    .font(.system(size: size * 0.34))
                    .offset(x: size * 0.34, y: -size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(
                context.state.isStale ? .white.opacity(0.3) : Brand.live,
                lineWidth: max(1.5, size * 0.09)
            )
        )
    }
}

/// Big number over a small unit — the same shape as the speed badge on the
/// map, so distance reads the same way everywhere in the app.
private struct DistanceStack: View {
    let state: MeetupActivityAttributes.ContentState
    var size: CGFloat

    var body: some View {
        if state.hasArrived {
            Text("🎉")
                .font(.system(size: size))
        } else if state.isStale {
            VStack(alignment: .trailing, spacing: 0) {
                Text(state.lastSeen, style: .relative)
                    .font(Brand.text(11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("AGO")
                    .font(Brand.text(8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.45))
            }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(state.distanceParts.value)
                    .font(Brand.display(size))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(state.distanceParts.unit)
                    .font(Brand.text(11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Which way to walk. Points at the friend's true bearing; falls back to a
/// dashed ring when there's nothing to point at, rather than lying with a
/// confident arrow at north.
private struct BearingArrow: View {
    let bearing: Double?
    let arrived: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 2)
                .frame(width: 26, height: 26)
            if arrived {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Brand.live)
            } else if let bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.coral)
                    .rotationEffect(.degrees(bearing))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

/// How much of the original gap is behind you. A bar rather than a number,
/// because "62%" is not a thing anyone wants to read while walking.
private struct TripProgress: View {
    let context: ActivityViewContext<MeetupActivityAttributes>

    private var value: Double {
        context.state.hasArrived ? 1 : context.state.progress(from: context.attributes.startDistance)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(context.state.hasArrived ? AnyShapeStyle(Brand.live) : AnyShapeStyle(Brand.gradient))
                    .frame(width: max(6, geo.size.width * value))
            }
        }
        .frame(height: 6)
    }
}

/// Lock Screen / banner presentation — the expanded island, laid out wide.
private struct LockScreenView: View {
    let context: ActivityViewContext<MeetupActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            AvatarBubble(context: context, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.hasArrived
                     ? "You found \(context.attributes.friendName)"
                     : "Heading to \(context.attributes.friendName)")
                    .font(Brand.display(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                TripProgress(context: context)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                DistanceStack(state: context.state, size: 24)
                BearingArrow(bearing: context.state.bearing, arrived: context.state.hasArrived)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
