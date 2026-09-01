import Foundation

/// The small slice of state the home-screen widget needs.
///
/// Written by the app after each friends refresh, read by the widget. Going
/// through an App Group file rather than letting the widget query Supabase
/// keeps the widget instant, works offline, and avoids maintaining a second
/// authenticated code path in an extension.
///
/// Compiled into both targets — keep it dependency-free.
enum NearbySnapshot {
    /// Must match the App Group added to both targets' entitlements.
    static let appGroup = "group.com.pinpop.app"

    struct Entry: Codable, Hashable {
        let name: String
        /// Metres.
        let distance: Double

        var distanceText: String {
            distance < 1000
                ? "\(Int(distance)) m"
                : String(format: "%.1f km", distance / 1000)
        }
    }

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("nearby.json")
    }

    static func save(_ entries: [Entry]) {
        guard let url else { return }
        // Closest first, and only a handful — the widget shows at most four.
        let trimmed = Array(entries.sorted { $0.distance < $1.distance }.prefix(6))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> [Entry] {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    static let placeholder: [Entry] = [
        .init(name: "Maya", distance: 689),
        .init(name: "Jun", distance: 1040),
    ]
}
