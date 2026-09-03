import Foundation

/// Port of the web app's `src/lib/streak.ts` — same tiers, same repair-grace
/// math, computed client-side from the same three columns
/// (`streak_days`, `last_interaction_on`, `streak_grace_value`/`_days`) so
/// native shows the exact same badge the web app would for this friend.
struct StreakInfo: Equatable {
    enum Tier: String { case none = "", spark, flame, blaze, legend }

    /// 0 when the server value is stale (no interaction yesterday or today) —
    /// the DB only corrects `streak_days` on the next interaction, so this
    /// treats anything older as already broken rather than showing a lie.
    var days = 0
    /// Interacted yesterday but not yet today — dies at UTC midnight unless
    /// something is sent before then.
    var atRisk = false
    /// Missed exactly one day, and today is still the last chance to start
    /// the three-day repair window before it's gone for good.
    var canRepair = false
    /// A repair is already underway (`streak_grace_value` is set server-side).
    var repairing = false
    var repairDaysLeft = 0
    var repairTarget = 0
    var icon = ""
    var tier: Tier = .none

    private static let dead = StreakInfo()

    private static func tier(for days: Int) -> (tier: Tier, icon: String) {
        let tier: Tier = days >= 30 ? .legend : days >= 14 ? .blaze : days >= 3 ? .flame : .spark
        let icon = tier == .legend ? "💯" : "🔥"
        return (tier, days >= 3 ? icon : "✨")
    }

    /// - Parameters:
    ///   - lastInteractionOn: a calendar date (time-of-day is ignored, same
    ///     as the web version comparing `YYYY-MM-DDT00:00:00Z` strings).
    static func compute(
        streakDays: Int?,
        lastInteractionOn: Date?,
        graceValue: Int?,
        graceDays: Int?
    ) -> StreakInfo {
        // A repair already in progress overrides everything else.
        if let graceValue, (graceDays ?? 0) > 0 {
            let left = max(0, 3 - (graceDays ?? 0))
            var info = dead
            info.repairing = true
            info.repairDaysLeft = left
            info.repairTarget = graceValue + 3
            info.icon = "🩹"
            return info
        }

        let days = streakDays ?? 0
        guard days > 0, let lastInteractionOn else { return dead }

        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let today = utc.startOfDay(for: .now)
        let last = utc.startOfDay(for: lastInteractionOn)
        let diff = utc.dateComponents([.day], from: last, to: today).day ?? 0

        if diff == 2 {
            // Exactly one day missed, repair not started yet: today is the
            // last chance to trigger the window.
            var info = dead
            info.canRepair = true
            info.repairTarget = days + 3
            info.icon = "💔"
            return info
        }
        // More than a day since the last interaction: dead, even if the
        // stored number hasn't been zeroed yet (only happens on next touch).
        if diff > 1 { return dead }

        let atRisk = diff == 1
        let (tier, icon) = tier(for: days)
        var info = dead
        info.days = days
        info.atRisk = atRisk
        info.icon = icon
        info.tier = tier
        return info
    }
}
