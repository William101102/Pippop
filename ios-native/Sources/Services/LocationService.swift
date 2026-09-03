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
    private var userId: UUID?

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
        manager.pausesLocationUpdatesAutomatically = true
        // NB: `allowsBackgroundLocationUpdates` is *not* set here. Setting it
        // before the user has granted an authorization that permits background
        // use throws an exception at runtime. It is enabled in
        // `enableBackgroundUpdatesIfPermitted()` once Always is granted.
    }

    /// Only legal once the user has actually granted Always. Called from the
    /// authorization callback rather than at init.
    private func enableBackgroundUpdatesIfPermitted() {
        let permitted = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = permitted
        manager.showsBackgroundLocationIndicator = permitted
    }

    func start(for userId: UUID) {
        self.userId = userId
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// Ask for Always only once the user has seen the value of live sharing —
    /// a cold "Always" prompt is both a poor experience and a review risk.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func stop() {
        manager.stopUpdatingLocation()
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.isDenied = (status == .denied || status == .restricted)
            self.enableBackgroundUpdatesIfPermitted()
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
