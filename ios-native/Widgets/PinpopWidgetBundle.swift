import SwiftUI
import WidgetKit

@main
struct PinpopWidgetBundle: WidgetBundle {
    var body: some Widget {
        BumpLiveActivity()
        MeetupLiveActivity()
        NearbyFriendsWidget()
    }
}

/// Home-screen widget: who is closest right now.
///
/// Reads a small snapshot the app writes to the shared App Group after each
/// friends refresh — the widget never talks to Supabase itself, which keeps it
/// fast, offline-tolerant, and free of a second auth path.
struct NearbyFriendsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NearbyFriends", provider: NearbyProvider()) { entry in
            NearbyFriendsView(entry: entry)
                .containerBackground(Brand.night, for: .widget)
        }
        .configurationDisplayName("Nearby friends")
        .description("The friends closest to you right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NearbyEntry: TimelineEntry {
    let date: Date
    let friends: [NearbySnapshot.Entry]
}

struct NearbyProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearbyEntry {
        NearbyEntry(date: .now, friends: NearbySnapshot.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyEntry) -> Void) {
        completion(NearbyEntry(date: .now, friends: NearbySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyEntry>) -> Void) {
        let entry = NearbyEntry(date: .now, friends: NearbySnapshot.load())
        // The app reloads timelines when it refreshes friends; this is just a
        // floor so a widget on a phone that hasn't opened the app still ages out.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct NearbyFriendsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NearbyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEARBY")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(Brand.pink)

            if entry.friends.isEmpty {
                Text("No one sharing right now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ForEach(entry.friends.prefix(family == .systemSmall ? 2 : 4), id: \.name) { friend in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Brand.gradient)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Text(friend.name.prefix(1).uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            )
                        Text(friend.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(friend.distanceText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
