import SwiftUI

/// The horizontally-scrolling "stories" rail — port of the web app's
/// `HighlightsRail`. Tapping your own ring opens the viewer if you already
/// have a live story, otherwise it starts the composer.
struct HighlightsRailView: View {
    let me: Profile
    let friends: [Friend]
    let highlightsByUser: [UUID: [Highlight]]
    var onAddMine: () -> Void
    var onOpen: (UUID) -> Void

    private var mine: [Highlight] { highlightsByUser[me.id] ?? [] }

    private var others: [Friend] {
        friends
            .filter { !(highlightsByUser[$0.id] ?? []).isEmpty }
            .sorted {
                (highlightsByUser[$0.id]?.first?.createdAt ?? .distantPast)
                    > (highlightsByUser[$1.id]?.first?.createdAt ?? .distantPast)
            }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                item(profile: me, live: !mine.isEmpty, label: "My story") {
                    mine.isEmpty ? onAddMine() : onOpen(me.id)
                }
                ForEach(others) { friend in
                    item(profile: friend.profile, live: true, label: friend.displayName) {
                        onOpen(friend.id)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func item(profile: Profile, live: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(profile: profile, size: 54)
                        .padding(3)
                        .overlay(
                            Circle().stroke(
                                live ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.ink.opacity(0.15)),
                                lineWidth: 2.5
                            )
                        )
                    if profile.id == me.id {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.violet)
                            .background(Circle().fill(.white))
                    }
                }
                Text(label)
                    .font(Theme.Font.body(9, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .pressable(scale: 0.95)
    }
}
