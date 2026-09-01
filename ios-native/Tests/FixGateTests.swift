import CoreLocation
import XCTest
@testable import Pinpop

/// The upload gate is the one piece of logic here worth pinning down: it
/// decides how much battery and quota the app burns, and it must behave
/// identically to the web implementation in `src/lib/location.ts`.
final class FixGateTests: XCTestCase {
    private func fix(lat: Double, lng: Double) -> Fix {
        Fix(CLLocation(latitude: lat, longitude: lng))
    }

    func testFirstFixAlwaysPersists() {
        var gate = FixGate()
        XCTAssertTrue(gate.shouldPersist(fix(lat: 34.0195, lng: -118.4912)))
    }

    func testTinyMovementIsDropped() {
        var gate = FixGate()
        let start = fix(lat: 34.0195, lng: -118.4912)
        let now = Date()
        XCTAssertTrue(gate.shouldPersist(start, now: now))
        gate.commit(start, now: now)

        // ~5 m north — below the 25 m threshold, and only a second later.
        let nudge = fix(lat: 34.019545, lng: -118.4912)
        XCTAssertFalse(gate.shouldPersist(nudge, now: now.addingTimeInterval(1)))
    }

    func testMovingFarEnoughPersists() {
        var gate = FixGate()
        let start = fix(lat: 34.0195, lng: -118.4912)
        let now = Date()
        gate.commit(start, now: now)

        // ~55 m north, comfortably over the 25 m threshold.
        let moved = fix(lat: 34.020, lng: -118.4912)
        XCTAssertTrue(gate.shouldPersist(moved, now: now.addingTimeInterval(2)))
    }

    func testStandingStillStillReportsAfterTheInterval() {
        var gate = FixGate()
        let start = fix(lat: 34.0195, lng: -118.4912)
        let now = Date()
        gate.commit(start, now: now)

        XCTAssertFalse(gate.shouldPersist(start, now: now.addingTimeInterval(44)))
        XCTAssertTrue(gate.shouldPersist(start, now: now.addingTimeInterval(46)))
    }
}
