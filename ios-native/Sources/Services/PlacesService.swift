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

    private static let recordedNightsKey = "pinpop-recorded-nights"
    /// How much of the night window has to be spent at a place before it
    /// counts as having slept there — 2 of the 4 hours.
    private static let minNightOverlap: TimeInterval = 2 * 3600

    /// Call on every fix. Cheap no-op outside the night window or once
    /// tonight's sample is already recorded.
    ///
    /// This is the weaker of the two paths: it only fires if the app happens
    /// to be receiving fixes during the small hours. `recordNights(from:)`
    /// below is the one that works while the app is closed.
    static func maybeRecordNightSample(_ fix: Fix, userId: UUID) {
        let now = Date()
        let calendar = Calendar.current
        guard nightHours.contains(calendar.component(.hour, from: now)) else { return }
        // "Last night" reads as the evening's date, not the morning's — a
        // 2 AM fix on the 4th is a sample of the night of the 3rd.
        guard let nightOf = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return }
        guard claimNight(nightOf, calendar: calendar) else { return }

        Task { await recordNight(fix: fix, userId: userId, nightOf: nightOf) }
    }

    /// The path that makes overnight places work **without the app running**.
    ///
    /// iOS delivers a `CLVisit` — arrival and departure at a place the user
    /// actually stopped at — by relaunching a terminated app, so a night at
    /// home is recorded even though nobody opened Pinpop at 3 AM. A visit can
    /// also span several days, in which case every night inside it counts and
    /// the streak advances properly.
    ///
    /// Requires Always authorisation; without it iOS never sends visits and
    /// only the sampling path above is left.
    static func recordNights(from visit: CLVisit, userId: UUID) {
        let now = Date()
        let calendar = Calendar.current
        // A visit still in progress reports `distantFuture` as its departure.
        let arrival = max(visit.arrivalDate, now.addingTimeInterval(-30 * 86_400))
        let departure = min(visit.departureDate, now)
        guard departure > arrival else { return }

        let fix = Fix(
            lat: visit.coordinate.latitude,
            lng: visit.coordinate.longitude,
            accuracy: visit.horizontalAccuracy,
            speed: nil
        )

        let pending = nights(between: arrival, and: departure, calendar: calendar)
        guard !pending.isEmpty else { return }

        // One task walking the nights oldest-first, not a task per night:
        // `recordNight` reads the current streak before writing the new one,
        // so three nights running in parallel would all read the same old
        // score and each write "old + 1" instead of building to "old + 3".
        Task {
            for nightOf in pending {
                guard claimNight(nightOf, calendar: calendar) else { continue }
                await recordNight(fix: fix, userId: userId, nightOf: nightOf)
            }
        }
    }

    /// Every night whose 1–5 AM window this stay covered for at least
    /// `minNightOverlap`. Walks local calendar days, so a stay that crosses a
    /// DST change or a time-zone move still lines up with the nights the
    /// person actually experienced.
    private static func nights(between arrival: Date, and departure: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: arrival)
        let lastDay = calendar.startOfDay(for: departure)

        while day <= lastDay {
            // The night *of* `day` is the window in the small hours of the
            // following morning.
            guard
                let morning = calendar.date(byAdding: .day, value: 1, to: day),
                let windowStart = calendar.date(bySettingHour: nightHours.lowerBound, minute: 0, second: 0, of: morning),
                let windowEnd = calendar.date(bySettingHour: nightHours.upperBound, minute: 0, second: 0, of: morning)
            else { break }

            let overlap = min(departure, windowEnd).timeIntervalSince(max(arrival, windowStart))
            if overlap >= minNightOverlap { result.append(day) }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Claims a night so it's only ever written once, returning false if it
    /// was already recorded. Both entry points funnel through this — the
    /// streak maths in `recordNight` assumes one write per night, and a visit
    /// callback can easily arrive twice for the same stay.
    private static func claimNight(_ nightOf: Date, calendar: Calendar) -> Bool {
        let key = nightKey(for: nightOf, calendar: calendar)
        let defaults = UserDefaults.standard
        var recorded = defaults.stringArray(forKey: recordedNightsKey) ?? []
        guard !recorded.contains(key) else { return false }
        recorded.append(key)
        defaults.set(recorded.suffix(60).map { $0 }, forKey: recordedNightsKey)
        return true
    }

    /// `last_seen_at` is stamped with **the night**, not with the moment the
    /// row is written. A visit callback can backfill three nights at once on
    /// the morning it fires; stamping all three "now" would make each one
    /// look like the same night to the streak check below, and the count
    /// would reset to 1 instead of building to 3. It also makes the 15-day
    /// staleness rule mean what it says — days since you last slept there,
    /// not days since the row was touched.
    private static func nightTimestamp(_ nightOf: Date, calendar: Calendar) -> Date {
        guard
            let morning = calendar.date(byAdding: .day, value: 1, to: nightOf),
            let start = calendar.date(bySettingHour: nightHours.lowerBound, minute: 0, second: 0, of: morning)
        else { return nightOf }
        return start
    }

    private static func recordNight(fix: Fix, userId: UUID, nightOf: Date) async {
        let calendar = Calendar.current
        let cellLat = cell(fix.lat)
        let cellLng = cell(fix.lng)
        let seenAt = nightTimestamp(nightOf, calendar: calendar)

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
            let cellLat: Int
            let cellLng: Int
            let score: Double
            let lastSeenAt: Date
        }

        try? await Backend.client
            .from("significant_places")
            .upsert(
                Upsert(userId: userId, kind: "overnight", lat: fix.lat, lng: fix.lng, cellLat: cellLat, cellLng: cellLng, score: newScore, lastSeenAt: seenAt),
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
    /// `significant_places`. `Int`, not `Int64` — `PostgrestFilterValue`
    /// (needed for the `.eq(...)` lookup below) isn't conformed by `Int64`
    /// in the SDK version this project pins; `Int` is 64-bit on iOS anyway,
    /// so nothing is actually lost.
    private static func cell(_ value: Double) -> Int { Int((value * 1000).rounded()) }
}
