import CoreLocation
import Foundation
import Supabase

/// Drops fixes that say nothing new.
///
/// Direct port of `createFixGate()` in `src/lib/location.ts` — keep the two in
/// sync. Every persisted fix fans out over Realtime to *every* friend, so an
/// ungated `CLLocationManager` stream is both a battery and a quota problem.
struct FixGate {
    static let minMoveMetres: CLLocationDistance = 25
    static let minInterval: TimeInterval = 45

    private var last: (at: Date, coordinate: CLLocationCoordinate2D)?

    mutating func shouldPersist(_ fix: Fix, now: Date = .now) -> Bool {
        guard let last else { return true }
        let moved = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            .distance(from: CLLocation(latitude: fix.lat, longitude: fix.lng))
        return moved >= Self.minMoveMetres || now.timeIntervalSince(last.at) >= Self.minInterval
    }

    mutating func commit(_ fix: Fix, now: Date = .now) {
        last = (now, fix.coordinate)
    }
}

@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var current: Fix?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isDenied = false

    /// Set from the privacy screen. `frozen` stops uploads entirely — the
    /// server keeps serving the last shared point to friends.
    var ghostMode: GhostMode = .precise

    private let manager = CLLocationManager()
    private var gate = FixGate()
    private var userId: UUID? {
        didSet { UserDefaults.standard.set(userId?.uuidString, forKey: Self.userIdKey) }
    }

    /// iOS relaunches the app **in the background** for a significant-location
    /// change or a visit, with no UI ever appearing — so `start(for:)`, which
    /// is called from the map screen, may never run on that launch. The signed
    /// -in id is cached here so `resume()` can pick monitoring back up from a
    /// cold background launch and still upload.
    private static let userIdKey = "pinpop-location-user"
    /// iOS grants the Always upgrade prompt **once per install**. After that,
    /// calling `requestAlwaysAuthorization()` does nothing at all, so the UI
    /// has to switch to sending people to Settings instead of showing a button
    /// that silently no-ops.
    private static let askedAlwaysKey = "pinpop-asked-always"

    /// Valid-looking speed readings from the last `confirmWindow` seconds —
    /// see `confirmSpeed(_:now:)`.
    private var recentMovingSpeeds: [(at: Date, speed: Double)] = []
    /// Walking pace, roughly — below this a reading is "standing still",
    /// whatever CoreLocation's confidence figure says about it.
    private static let minMovingSpeedMps: Double = 1.2
    private static let confirmWindow: TimeInterval = 90

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = FixGate.minMoveMetres
        // Live sharing is the whole product, so don't let iOS park the stream
        // on its own judgement — `FixGate` is what keeps the upload rate (and
        // the battery cost) sane, not paused updates.
        manager.pausesLocationUpdatesAutomatically = false
        // Tells CoreLocation what kind of movement to expect so it tunes its
        // filtering — `.other` covers a person going about their day on foot,
        // in a car or on a bike, which is exactly this app.
        manager.activityType = .other
        // NB: `allowsBackgroundLocationUpdates` is *not* set here. Setting it
        // before the user has granted an authorization that permits background
        // use throws an exception at runtime. It is enabled in
        // `applyAuthorization()` once Always is granted.
        authorization = manager.authorizationStatus
    }

    /// True once the user has granted Always. Everything background — staying
    /// live for friends while the app is closed, and the overnight-place
    /// detection — depends on this and nothing else.
    var runsInBackground: Bool { authorization == .authorizedAlways }

    /// iOS only ever shows the Always prompt once. After that this is false
    /// and the only route left is Settings.
    var canAskForAlways: Bool {
        authorization == .authorizedWhenInUse
            && !UserDefaults.standard.bool(forKey: Self.askedAlwaysKey)
    }

    /// Background monitoring, switched on the moment Always is granted:
    ///
    /// - **Significant location changes** and **visits** are the two APIs that
    ///   relaunch a *terminated* app. They're coarse (roughly cell-tower
    ///   resolution, and arrival/departure at a place) and nearly free on
    ///   battery, and they're what makes "still works when the app is closed"
    ///   true at all — plain `startUpdatingLocation` dies with the process.
    /// - `allowsBackgroundLocationUpdates` keeps the fine-grained stream alive
    ///   while the app is merely backgrounded. iOS shows the blue status-bar
    ///   indicator throughout; that's deliberate on Apple's part and can't be
    ///   turned off.
    private func applyAuthorization() {
        let status = manager.authorizationStatus
        authorization = status
        isDenied = (status == .denied || status == .restricted)

        let always = status == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = always
        manager.showsBackgroundLocationIndicator = always

        if always {
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
        }
    }

    func start(for userId: UUID) {
        self.userId = userId
        // Always ask for When In Use first. Asking for Always cold gets you a
        // prompt that doesn't even offer it (iOS shows the when-in-use choices
        // and quietly grants "provisional" Always), and it burns the one
        // upgrade prompt on a moment when nobody knows what the app does yet.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        applyAuthorization()
    }

    /// Restarts monitoring on a launch where the map may never appear —
    /// specifically the background relaunches iOS does for a significant
    /// location change or a visit. Safe to call repeatedly.
    func resume() {
        if userId == nil,
           let stored = UserDefaults.standard.string(forKey: Self.userIdKey),
           let id = UUID(uuidString: stored) {
            userId = id
        }
        guard userId != nil, manager.authorizationStatus != .notDetermined else { return }
        manager.startUpdatingLocation()
        applyAuthorization()
    }

    /// Ask for Always only once the user has seen the value of live sharing —
    /// a cold Always prompt is a poor experience, an App Review risk, and
    /// (since iOS 13) doesn't even show the Always option.
    ///
    /// Only meaningful while `canAskForAlways` is true: iOS shows this prompt
    /// once per install and silently ignores every later call, which is why
    /// the attempt is recorded here rather than assumed to have worked.
    func requestAlways() {
        guard authorization == .authorizedWhenInUse else { return }
        UserDefaults.standard.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        userId = nil
    }

    /// Requires two walking-pace-or-faster readings inside the last 90
    /// seconds before a speed is trusted enough to show — on the map, on a
    /// friend's pin, anywhere. `Fix.init` already drops speeds CoreLocation
    /// itself isn't confident about; this is the second line of defense,
    /// for the case that *does* come back looking confident but is really a
    /// one-off (a shake, a reflection off a building). Two bad readings in a
    /// row inside 90 seconds essentially never happens; genuinely starting
    /// to walk, drive, or ride does.
    private func confirmSpeed(_ fix: Fix, now: Date) -> Double? {
        if let speed = fix.speed, speed >= Self.minMovingSpeedMps {
            recentMovingSpeeds.append((now, speed))
        }
        recentMovingSpeeds.removeAll { now.timeIntervalSince($0.at) > Self.confirmWindow }
        guard recentMovingSpeeds.count >= 2, let latest = recentMovingSpeeds.last else { return nil }
        return latest.speed
    }

    private func persist(_ fix: Fix) async {
        guard let userId, ghostMode != .frozen else { return }

        struct Row: Encodable {
            let userId: UUID
            let lat: Double
            let lng: Double
            let accuracy: Double?
            let speed: Double?
            let updatedAt: Date
        }

        let row = Row(
            userId: userId, lat: fix.lat, lng: fix.lng,
            accuracy: fix.accuracy, speed: fix.speed, updatedAt: .now
        )

        do {
            try await Backend.client
                .from("locations")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            // Best effort: a dropped upload is corrected by the next fix.
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newest = locations.last else { return }
        let fix = Fix(newest)
        Task { @MainActor in
            let now = Date()
            // The gate (movement/interval) always runs against the raw fix —
            // speed confidence has nothing to do with whether this position
            // update is worth persisting.
            let confirmed = self.confirmSpeed(fix, now: now)
            let displayFix = Fix(lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy, speed: confirmed)
            self.current = displayFix
            self.isDenied = false
            if let userId = self.userId {
                PlacesService.maybeRecordNightSample(fix, userId: userId)
            }
            guard self.gate.shouldPersist(fix) else { return }
            self.gate.commit(fix)
            await self.persist(displayFix)
        }
    }

    /// Arrival at / departure from a place the user actually stayed put in.
    /// Cheap enough to leave on permanently, and — crucially — iOS delivers
    /// these by **relaunching a terminated app**, which is what lets an
    /// overnight stay be recorded on a night nobody opened Pinpop.
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            guard let userId = self.userId else { return }
            PlacesService.recordNights(from: visit, userId: userId)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.applyAuthorization()
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in self.isDenied = true }
    }
}
