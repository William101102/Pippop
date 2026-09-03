import CoreLocation
import Foundation
import Supabase

/// Where someone sleeps — the small house pin the map shows once a spot has
/// had a night at it, upgrading to "Home" after enough nights running.
///
/// Mirrors `public.significant_places`. `kind` is always `'overnight'` now —
/// migration `202608300007_overnight_places_only` retired standalone
/// home/work detection server-side and locked the column's check constraint
/// to that one value — so "home" isn't a separate row or kind, it's just a
/// read of `score` once it clears `PlacesService.homeStreakNights`.
struct SignificantPlace: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    var lat: Double
    var lng: Double
    /// Consecutive nights at this spot. Resets to 1 the moment a night is
    /// skipped, so it only ever reflects an unbroken streak.
    var score: Double
    var firstSeenAt: Date
    var lastSeenAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    var isHome: Bool { score >= PlacesService.homeStreakNights }
}

extension SignificantPlace {
    /// Same "fell off the map" rule `PlacesService.loadVisible()` applies
    /// server-round-trip; exposed so a caller holding an already-fetched
    /// list (e.g. after a local score bump) can re-check without refetching.
    var isStale: Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Int(PlacesService.staleAfterDays), to: .now) ?? .now
        return lastSeenAt < cutoff
    }
}

/// Detects "you slept here" from the fixes `LocationService` already
/// receives — no separate background job, no extra permission. It only ever
/// acts during a narrow overnight window, and only once per calendar night.
///
/// This is necessarily best-effort: it can only see a fix if the app is
/// actually running (foreground, or background with Always access and
/// `allowsBackgroundLocationUpdates`) during that window. There's no server
/// cron doing this instead — a missed night just means that night doesn't
/// count, it doesn't break the streak retroactively or write anything wrong.
@MainActor
enum PlacesService {
    /// Consecutive nights in the same spot before a pin reads "Home"
    /// instead of "Night place". `nonisolated` — it's a plain constant, and
    /// `SignificantPlace.isHome`/`isStale` (on a non-isolated struct) need
    /// to read it without hopping to the main actor.
    nonisolated static let homeStreakNights: Double = 7
    /// A place that has gone this long without a fresh night sample drops
    /// off the map. Rows aren't deleted for this — `loadVisible()` simply
    /// stops returning them — so a place quietly reappears if you do go
    /// back before it's pruned some other way.
    nonisolated static let staleAfterDays: Double = 15

    /// Local-time hours treated as "asleep". Narrow enough that a late
    /// night out or an early commute isn't mistaken for a stay; wide enough
    /// to have a decent chance of catching *a* fix in it despite there
    /// being no dedicated background job. Always read against the device's
    /// own calendar/time zone, never UTC, so "night" means the same thing
    /// it does to the person holding the phone.
    private static let nightHours = 1..<5

    private static let lastRecordedKey = "pinpop-last-night-sample"

    /// Call on every fix. Cheap no-op outside the night window or once
    /// tonight's sample is already recorded.
    static func maybeRecordNightSample(_ fix: Fix, userId: UUID) {
        let now = Date()
        let calendar = Calendar.current
        guard nightHours.contains(calendar.component(.hour, from: now)) else { return }
        // "Last night" reads as the evening's date, not the morning's — a
        // 2 AM fix on the 4th is a sample of the night of the 3rd.
        guard let nightOf = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return }

        let key = nightKey(for: nightOf, calendar: calendar)
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastRecordedKey) != key else { return }
        defaults.set(key, forKey: lastRecordedKey)

        Task { await recordNight(fix: fix, userId: userId, nightOf: nightOf) }
    }

    private static func recordNight(fix: Fix, userId: UUID, nightOf: Date) async {
        let calendar = Calendar.current
        let cellLat = cell(fix.lat)
        let cellLng = cell(fix.lng)

        let existing: [SignificantPlace] = (try? await Backend.client
            .from("significant_places")
            .select()
            .eq("user_id", value: userId)
            .eq("kind", value: "overnight")
            .eq("cell_lat", value: cellLat)
            .eq("cell_lng", value: cellLng)
            .limit(1)
            .execute()
            .value) ?? []

        let newScore: Double
        if let row = existing.first {
            let previousNight = calendar.date(byAdding: .day, value: -1, to: nightOf) ?? nightOf
            let rowNightOf = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: row.lastSeenAt)) ?? row.lastSeenAt
            newScore = calendar.isDate(rowNightOf, inSameDayAs: previousNight) ? row.score + 1 : 1
        } else {
            newScore = 1
        }

        struct Upsert: Encodable {
            let userId: UUID
            let kind: String
            let lat: Double
            let lng: Double
            let cellLat: Int64
            let cellLng: Int64
            let score: Double
            let lastSeenAt: Date
        }

        try? await Backend.client
            .from("significant_places")
            .upsert(
                Upsert(userId: userId, kind: "overnight", lat: fix.lat, lng: fix.lng, cellLat: cellLat, cellLng: cellLng, score: newScore, lastSeenAt: .now),
                onConflict: "user_id,kind,cell_lat,cell_lng"
            )
            .execute()
    }

    /// My own night places plus my friends' — RLS ("friends read significant
    /// places") already limits the friend half to accepted friendships that
    /// still share location with me, the same rule zones use. Stale rows are
    /// filtered out here rather than deleted server-side.
    static func loadVisible() async throws -> [SignificantPlace] {
        let rows: [SignificantPlace] = try await Backend.client
            .from("significant_places")
            .select()
            .eq("kind", value: "overnight")
            .execute()
            .value
        return rows.filter { !$0.isStale }
    }

    private static func nightKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    /// ~111 m grid — coarse enough to absorb ordinary GPS drift around a
    /// building, fine enough to keep separate addresses apart. Mirrors the
    /// `cell_lat`/`cell_lng` bigint columns already reserved for this on
    /// `significant_places`.
    private static func cell(_ value: Double) -> Int64 { Int64((value * 1000).rounded()) }
}
