import CoreLocation
import Foundation
import Supabase

/// A place someone keeps coming back to — where they sleep, and where they
/// spend their working days.
///
/// Mirrors `public.significant_places`. Home isn't a `kind` of its own: an
/// overnight place *becomes* home once its consecutive-night streak clears
/// `PlacesService.homeStreakNights`, which is why the count lives in `score`
/// and the promotion is a read rather than a second row.
struct SignificantPlace: Codable, Identifiable, Hashable, Sendable {
    /// The two the database accepts — see the `significant_places_kind_check`
    /// constraint in `backend/supabase/setup.sql`.
    enum Kind: String, Codable, Sendable {
        case overnight, work
    }

    let id: UUID
    let userId: UUID
    var kind: Kind
    var lat: Double
    var lng: Double
    /// Consecutive nights (overnight) or working days (work) at this spot.
    /// Resets to 1 the moment one is skipped, so it only ever reflects an
    /// unbroken streak.
    var score: Double
    var firstSeenAt: Date
    var lastSeenAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    var isHome: Bool { kind == .overnight && score >= PlacesService.homeStreakNights }
    var isWorkplace: Bool { kind == .work && score >= PlacesService.workStreakDays }

    /// A work row only means anything once it's earned the title — a single
    /// afternoon somewhere isn't a workplace, so it draws nothing until then.
    var isDisplayable: Bool { kind == .overnight || isWorkplace }
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
    /// Consecutive **weekdays** spent somewhere in working hours before it's
    /// called a workplace. Weekends are skipped rather than counted as a
    /// break — a literal 7-days-in-a-row rule would never fire for anyone
    /// with a normal Mon–Fri job.
    nonisolated static let workStreakDays: Double = 7
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

    /// Local-time hours treated as "at work" — the middle of the day, well
    /// clear of either commute, so passing through somewhere at 9 or 18 isn't
    /// mistaken for working there.
    private static let workHours = 10..<16
    private static let recordedNightsKey = "pinpop-recorded-nights"
    /// How much of the night window has to be spent at a place before it
    /// counts as having slept there — 2 of the 4 hours.
    private static let minNightOverlap: TimeInterval = 2 * 3600
    /// Likewise for the working day — 3 of the 6 hours.
    private static let minWorkOverlap: TimeInterval = 3 * 3600
    /// The furthest back a single visit callback is allowed to fill in. A
    /// visit is normally delivered within hours of the stay ending, so
    /// anything older is either an unknown arrival date or something odd —
    /// and inventing days is how a brand-new place became "Home" overnight.
    private static let maxBackfillDays: Double = 2

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
        guard claim(nightOf, kind: .overnight, calendar: calendar) else { return }

        Task { await record(fix: fix, userId: userId, on: nightOf, kind: .overnight) }
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
        let calendar = Calendar.current
        guard let (arrival, departure, fix) = span(of: visit) else { return }

        let pending = nights(between: arrival, and: departure, calendar: calendar)
        guard !pending.isEmpty else { return }

        // One task walking the nights oldest-first, not a task per night:
        // `recordNight` reads the current streak before writing the new one,
        // so three nights running in parallel would all read the same old
        // score and each write "old + 1" instead of building to "old + 3".
        Task {
            for nightOf in pending {
                guard claim(nightOf, kind: .overnight, calendar: calendar) else { continue }
                await record(fix: fix, userId: userId, on: nightOf, kind: .overnight)
            }
        }
    }

    /// Working days, the same way: a `CLVisit` that covered the middle of the
    /// day. Only weekdays count, and only the streak matters — the pin
    /// doesn't appear at all until it reaches `workStreakDays`.
    static func recordWorkdays(from visit: CLVisit, userId: UUID) {
        let calendar = Calendar.current
        guard let (arrival, departure, fix) = span(of: visit) else { return }

        let pending = workdays(between: arrival, and: departure, calendar: calendar)
        guard !pending.isEmpty else { return }

        Task {
            for day in pending {
                guard claim(day, kind: .work, calendar: calendar) else { continue }
                await record(fix: fix, userId: userId, on: day, kind: .work)
            }
        }
    }

    /// The usable window of a visit, plus the coordinate to file it under.
    ///
    /// **Never extrapolate backwards.** `CLVisit.arrivalDate` is
    /// `distantPast` when iOS doesn't know when the stay began — the first
    /// cut clamped that to "30 days ago", which then backfilled a month of
    /// nights that never happened and promoted a one-day-old place straight
    /// to Home. An unknown arrival now yields at most the last
    /// `maxBackfillDays`, and a known one is trusted as far back as that cap.
    private static func span(of visit: CLVisit) -> (arrival: Date, departure: Date, fix: Fix)? {
        let now = Date()
        let floor = now.addingTimeInterval(-maxBackfillDays * 86_400)
        // `distantPast` means "unknown", not "long ago" — treat it as the cap
        // rather than as evidence of a stay stretching back that far.
        let arrival = max(visit.arrivalDate, floor)
        // A visit still in progress reports `distantFuture` as its departure.
        let departure = min(visit.departureDate, now)
        guard departure > arrival else { return nil }

        let fix = Fix(
            lat: visit.coordinate.latitude,
            lng: visit.coordinate.longitude,
            accuracy: visit.horizontalAccuracy,
            speed: nil
        )
        return (arrival, departure, fix)
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

    /// Every weekday whose working-hours window this stay covered. Weekends
    /// are skipped entirely rather than counted as a miss, so a Friday and
    /// the following Monday are consecutive as far as the streak is
    /// concerned — see `workStreakDays`.
    private static func workdays(between arrival: Date, and departure: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: arrival)
        let lastDay = calendar.startOfDay(for: departure)

        while day <= lastDay {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? .distantFuture }
            guard !isWeekend(day, calendar: calendar) else { continue }
            guard
                let windowStart = calendar.date(bySettingHour: workHours.lowerBound, minute: 0, second: 0, of: day),
                let windowEnd = calendar.date(bySettingHour: workHours.upperBound, minute: 0, second: 0, of: day)
            else { break }

            let overlap = min(departure, windowEnd).timeIntervalSince(max(arrival, windowStart))
            if overlap >= minWorkOverlap { result.append(day) }
        }
        return result
    }

    private static func isWeekend(_ day: Date, calendar: Calendar) -> Bool {
        calendar.isDateInWeekend(day)
    }

    /// The day that has to be the immediate predecessor of `day` for a streak
    /// to continue. For work that's the previous *weekday*, so Monday follows
    /// Friday; for overnight it's simply yesterday.
    private static func previousDay(before day: Date, kind: SignificantPlace.Kind, calendar: Calendar) -> Date {
        var candidate = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        guard kind == .work else { return candidate }
        var guardRail = 0
        while isWeekend(candidate, calendar: calendar), guardRail < 7 {
            candidate = calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate
            guardRail += 1
        }
        return candidate
    }

    /// Claims a day so it's only ever written once, returning false if it was
    /// already recorded. Every entry point funnels through this — the streak
    /// maths in `record` assumes one write per day, and a visit callback can
    /// easily arrive twice for the same stay.
    private static func claim(_ day: Date, kind: SignificantPlace.Kind, calendar: Calendar) -> Bool {
        let key = "\(kind.rawValue):\(nightKey(for: day, calendar: calendar))"
        let defaults = UserDefaults.standard
        var recorded = defaults.stringArray(forKey: recordedNightsKey) ?? []
        guard !recorded.contains(key) else { return false }
        recorded.append(key)
        defaults.set(Array(recorded.suffix(120)), forKey: recordedNightsKey)
        return true
    }

    /// `last_seen_at` is stamped with **the night**, not with the moment the
    /// row is written. A visit callback can backfill three nights at once on
    /// the morning it fires; stamping all three "now" would make each one
    /// look like the same night to the streak check below, and the count
    /// would reset to 1 instead of building to 3. It also makes the 15-day
    /// staleness rule mean what it says — days since you last slept there,
    /// not days since the row was touched.
    /// The canonical instant to stamp a recorded day with — the start of the
    /// window it was recorded for, not the moment the row is written. A visit
    /// callback can backfill three days at once on the morning it fires;
    /// stamping all three "now" would make each look like the same day to the
    /// streak check, and the count would reset to 1 instead of building to 3.
    /// It also makes the 15-day staleness rule mean what it says — days since
    /// you were last there, not days since the row was touched.
    private static func timestamp(for day: Date, kind: SignificantPlace.Kind, calendar: Calendar) -> Date {
        switch kind {
        case .overnight:
            guard
                let morning = calendar.date(byAdding: .day, value: 1, to: day),
                let start = calendar.date(bySettingHour: nightHours.lowerBound, minute: 0, second: 0, of: morning)
            else { return day }
            return start
        case .work:
            return calendar.date(bySettingHour: workHours.lowerBound, minute: 0, second: 0, of: day) ?? day
        }
    }

    /// The day a stored row was recorded for, recovered from its timestamp —
    /// the inverse of `timestamp(for:kind:calendar:)`.
    private static func day(of storedAt: Date, kind: SignificantPlace.Kind, calendar: Calendar) -> Date {
        switch kind {
        case .overnight:
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: storedAt)) ?? storedAt
        case .work:
            return calendar.startOfDay(for: storedAt)
        }
    }

    private static func record(fix: Fix, userId: UUID, on day: Date, kind: SignificantPlace.Kind) async {
        let calendar = Calendar.current
        let cellLat = cell(fix.lat)
        let cellLng = cell(fix.lng)
        let seenAt = timestamp(for: day, kind: kind, calendar: calendar)

        let existing: [SignificantPlace] = (try? await Backend.client
            .from("significant_places")
            .select()
            .eq("user_id", value: userId)
            .eq("kind", value: kind.rawValue)
            .eq("cell_lat", value: cellLat)
            .eq("cell_lng", value: cellLng)
            .limit(1)
            .execute()
            .value) ?? []

        let newScore: Double
        if let row = existing.first {
            let expected = previousDay(before: day, kind: kind, calendar: calendar)
            let recorded = Self.day(of: row.lastSeenAt, kind: kind, calendar: calendar)
            newScore = calendar.isDate(recorded, inSameDayAs: expected) ? row.score + 1 : 1
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
                Upsert(userId: userId, kind: kind.rawValue, lat: fix.lat, lng: fix.lng, cellLat: cellLat, cellLng: cellLng, score: newScore, lastSeenAt: seenAt),
                onConflict: "user_id,kind,cell_lat,cell_lng"
            )
            .execute()
    }

    /// My own places plus my friends' — RLS ("friends read significant
    /// places") already limits the friend half to accepted friendships that
    /// still share location with me, the same rule zones use. Stale rows are
    /// filtered out here rather than deleted server-side.
    static func loadVisible() async throws -> [SignificantPlace] {
        let rows: [SignificantPlace] = try await Backend.client
            .from("significant_places")
            .select()
            .execute()
            .value
        return collapse(rows.filter { !$0.isStale && $0.isDisplayable })
    }

    /// GPS drift can push the same building across a grid-cell boundary,
    /// leaving two rows a hundred metres apart — which is how a home badge
    /// and a night-place badge ended up stacked on one spot. Per person,
    /// across kinds, keep the strongest row and drop anything within
    /// `mergeRadius` of one already kept: one place, one pin. (Someone whose
    /// home *is* their workplace therefore shows as home, which is the more
    /// meaningful of the two.)
    private static let mergeRadius: CLLocationDistance = 200

    private static func collapse(_ places: [SignificantPlace]) -> [SignificantPlace] {
        var kept: [SignificantPlace] = []
        for place in places.sorted(by: { $0.score > $1.score }) {
            let clash = kept.contains { other in
                other.userId == place.userId
                    && CLLocation(latitude: other.lat, longitude: other.lng)
                        .distance(from: CLLocation(latitude: place.lat, longitude: place.lng)) < mergeRadius
            }
            if !clash { kept.append(place) }
        }
        return kept
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
