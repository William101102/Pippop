import CoreLocation
import Foundation
import Supabase

/// Sets your status for you: 🏠 when you get home, 💼 when you get to work,
/// 💤 once you've clearly gone to sleep, back to 🏠 when you stir.
///
/// ## What it's allowed to know
///
/// iOS gives an app **no way to see whether the phone is being used** — not
/// screen-on state, not other apps, not unlocks. So "30 minutes without
/// touching your phone" can't be read directly, and anything claiming to is
/// guessing. What can be known, and what this uses instead:
///
/// - **Motion.** `CMMotionActivityManager` records continuously at the
///   coprocessor and can be *queried for the past*, so even a launch that
///   happens minutes later can ask "was this phone stationary for the last
///   half hour?" A phone being picked up, carried, or typed on does not stay
///   `stationary`; a phone on a nightstand does. That's the real signal here.
/// - **Our own foreground time**, which at least rules out "they're in Pinpop
///   right now".
/// - **The clock**, in local time, and where they are.
///
/// Together those are a good proxy and an honest one: asleep = night + at
/// home (or nowhere known) + not moved for half an hour + not in the app.
///
/// ## Not stepping on the person
///
/// A status the user typed themselves must not be silently overwritten. The
/// rule is that this only ever writes when the *derived context changes* —
/// arriving somewhere, falling asleep, waking up. Set your own status to
/// "🍔 Eating" while sat at home and it stands until you actually go
/// somewhere, because nothing about the context has changed in between.
@MainActor
@Observable
final class AutoStatusService {
    static let shared = AutoStatusService()

    /// What the app believes you're doing. Deliberately coarse — every extra
    /// state is another chance to be confidently wrong about someone's life.
    enum Context: String, Sendable {
        case home, stayingOver, work, asleep

        var status: (emoji: String, text: String) {
            switch self {
            case .home: ("🏠", "At home")
            case .stayingOver: ("🌙", "Staying over")
            case .work: ("💼", "Working")
            case .asleep: ("💤", "Asleep")
            }
        }
    }

    private static let enabledKey = "pinpop-auto-status"
    private static let appliedKey = "pinpop-auto-status-applied"
    private static let lastActiveKey = "pinpop-last-app-active"

    /// How still, and for how long, before we'll call it sleep.
    private static let sleepStillness: TimeInterval = 30 * 60
    /// Local hours sleep is even considered in, as two bounds rather than a
    /// `Range`: this window wraps midnight, and `21...9` is not a range Swift
    /// will build — a `ClosedRange` traps on construction when `lowerBound >
    /// upperBound`. Kept wide because the stillness test does the real work;
    /// this only stops an afternoon nap, or a long film, reading as 💤 at 3pm.
    private static let sleepFromHour = 21
    private static let sleepUntilHour = 9
    /// How close to a place counts as being there. Generous on purpose: a
    /// fix indoors drifts, and flapping between "At home" and nothing is
    /// worse than being slightly early.
    private static let arrivalRadius: CLLocationDistance = 160
    private static let placeCacheLifetime: TimeInterval = 30 * 60

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            guard isEnabled else { return }
            // Switching it back on should do something visible: clearing the
            // last applied context makes wherever you are right now count as
            // a fresh arrival.
            applied = nil
            Task { await evaluate() }
        }
    }

    private var applied: Context? {
        didSet { UserDefaults.standard.set(applied?.rawValue, forKey: Self.appliedKey) }
    }

    private var places: [SignificantPlace] = []
    private var placesFetchedAt: Date?
    private var evaluating = false
    private var timer: Timer?

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        applied = defaults.string(forKey: Self.appliedKey).flatMap(Context.init(rawValue:))
    }

    /// A slow heartbeat, for the one transition no external event announces:
    /// falling asleep. Arriving somewhere produces a location callback;
    /// going to sleep produces, by definition, nothing at all. This only
    /// fires while the process is alive, which — with Always authorisation
    /// and background location updates — is most of the time.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            Task { @MainActor in await AutoStatusService.shared.evaluate() }
        }
    }

    /// Call whenever the app comes to the foreground: it's both a "definitely
    /// awake" signal and the clock this uses for "not in the app recently".
    func noteAppActive() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastActiveKey)
        Task { await evaluate() }
    }

    func evaluate(userId: UUID? = nil, fix: Fix? = nil) async {
        guard isEnabled, !evaluating else { return }
        guard let me = userId ?? cachedUserId else { return }
        evaluating = true
        defer { evaluating = false }

        await refreshPlacesIfStale(for: me)
        let here = fix ?? lastFix
        if let fix { lastFix = fix }

        guard let context = await derive(from: here) else {
            // Out in the world, away from anywhere known. Nothing to write —
            // but forget what was last applied, so coming home later counts
            // as a fresh arrival and restores 🏠 even if you set your own
            // status to something else while you were out.
            applied = nil
            return
        }
        guard context != applied else { return }

        let status = context.status
        do {
            struct Update: Encodable {
                let statusEmoji: String
                let statusText: String
            }
            try await Backend.client
                .from("profiles")
                .update(Update(statusEmoji: status.emoji, statusText: status.text))
                .eq("id", value: me)
                .execute()
            applied = context
        } catch {
            // Next evaluation tries again; a missed status is not worth a retry loop.
        }
    }

    // MARK: - Deriving

    private func derive(from fix: Fix?) async -> Context? {
        let atPlace = fix.flatMap(place(at:))

        if await isAsleep(atPlace: atPlace) { return .asleep }

        guard let atPlace else {
            // Out and about. Nothing to say that the person hasn't already
            // said better themselves, so leave whatever's there alone.
            return nil
        }
        if atPlace.isWorkplace { return .work }
        return atPlace.isHome ? .home : .stayingOver
    }

    /// Night + still + not in the app. `atPlace` is allowed to be nil — people
    /// sleep in hotels and on sofas — but a workplace rules it out, because
    /// a phone sat on a desk during a late shift is not a person asleep.
    private func isAsleep(atPlace: SignificantPlace?) async -> Bool {
        guard atPlace?.isWorkplace != true else { return false }

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        // Wraps midnight, hence `||` rather than a range check.
        let isNight = hour >= Self.sleepFromHour || hour <= Self.sleepUntilHour
        guard isNight else { return false }

        let lastActive = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.lastActiveKey))
        guard now.timeIntervalSince(lastActive) >= Self.sleepStillness else { return false }

        return await MotionActivityService.hasBeenStill(since: now.addingTimeInterval(-Self.sleepStillness))
    }

    private func place(at fix: Fix) -> SignificantPlace? {
        let here = CLLocation(latitude: fix.lat, longitude: fix.lng)
        return places
            .filter { $0.isHome || $0.isWorkplace || $0.kind == .overnight }
            .map { ($0, here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))) }
            .filter { $0.1 <= Self.arrivalRadius }
            .min { $0.1 < $1.1 }?
            .0
    }

    // MARK: - Cached inputs

    private var lastFix: Fix?

    private var cachedUserId: UUID? {
        UserDefaults.standard.string(forKey: "pinpop-location-user").flatMap(UUID.init(uuidString:))
    }

    private func refreshPlacesIfStale(for userId: UUID) async {
        if let fetched = placesFetchedAt, Date.now.timeIntervalSince(fetched) < Self.placeCacheLifetime {
            return
        }
        let visible = (try? await PlacesService.loadVisible()) ?? []
        places = visible.filter { $0.userId == userId }
        placesFetchedAt = .now
    }
}
