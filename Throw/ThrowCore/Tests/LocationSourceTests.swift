import CoreLocation
import Foundation
import Testing
@testable import ThrowCore

struct LocationSourceTests {
    @Test func acceptsFixAtTargetAccuracy() throws {
        let fix = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 100,
            observedAt: ThrowCoreFixture.date,
        )
        #expect(
            LocationFixEvaluator.decision(
                bestFix: fix,
                elapsed: 1,
                at: ThrowCoreFixture.date,
            ) == .acceptTarget(fix),
        )
    }

    @Test func offersBestFixAfterTwentySeconds() throws {
        let fix = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 250,
            observedAt: ThrowCoreFixture.date,
        )
        #expect(
            LocationFixEvaluator.decision(
                bestFix: fix,
                elapsed: 20,
                at: ThrowCoreFixture.date,
            ) == .offerBest(fix),
        )
    }

    @Test func continuesWaitingWithoutTargetBeforeDeadline() {
        #expect(
            LocationFixEvaluator.decision(
                bestFix: nil,
                elapsed: 19.9,
                at: ThrowCoreFixture.date,
            ) == .keepWaiting(best: nil),
        )
    }

    @Test func decisionRevalidatesTheBestFixAtDecisionTime() throws {
        let staleFix = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date.addingTimeInterval(
                -(LocationFixEvaluator.maximumSampleAge + 1),
            ),
        )

        #expect(
            LocationFixEvaluator.decision(
                bestFix: staleFix,
                elapsed: LocationFixEvaluator.maximumWait,
                at: ThrowCoreFixture.date,
            ) == .offerBest(nil),
        )
    }

    @Test func rejectsCachedAndMateriallyFutureFixes() throws {
        let cached = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date.addingTimeInterval(-16),
        )
        let future = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date.addingTimeInterval(6),
        )
        let current = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date,
        )

        #expect(LocationFixEvaluator.isValid(cached, at: ThrowCoreFixture.date) == false)
        #expect(LocationFixEvaluator.isValid(future, at: ThrowCoreFixture.date) == false)
        #expect(LocationFixEvaluator.isValid(current, at: ThrowCoreFixture.date))
    }

    @Test func staleAccurateSampleCannotHideFreshUsableSample() throws {
        let stale = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
            altitude: 20,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: ThrowCoreFixture.date.addingTimeInterval(-16),
        )
        let fresh = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.1),
            altitude: 20,
            horizontalAccuracy: 50,
            verticalAccuracy: 1,
            timestamp: ThrowCoreFixture.date,
        )

        let selected = try #require(
            LocationFixEvaluator.bestValidFix(
                from: [stale, fresh],
                at: ThrowCoreFixture.date,
            ),
        )
        #expect(selected.horizontalAccuracyMeters == 50)
        #expect(selected.position.coordinate.latitude == 37.1)
    }

    @Test func invalidAltitudeCannotHideAValidLessAccurateSample() throws {
        let invalidAltitude = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
            altitude: 500,
            horizontalAccuracy: 1,
            verticalAccuracy: -1,
            timestamp: ThrowCoreFixture.date,
        )
        let valid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.1),
            altitude: 20,
            horizontalAccuracy: 50,
            verticalAccuracy: 10,
            timestamp: ThrowCoreFixture.date,
        )

        let selected = try #require(
            LocationFixEvaluator.bestValidFix(
                from: [invalidAltitude, valid],
                at: ThrowCoreFixture.date,
            ),
        )

        #expect(selected.horizontalAccuracyMeters == 50)
        #expect(selected.position.coordinate.latitude == 37.1)
        #expect(abs(selected.position.altitude.meters - 20) < 0.000_001)
    }

    @Test func freshnessBoundariesAreInclusive() throws {
        let oldest = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date.addingTimeInterval(
                -LocationFixEvaluator.maximumSampleAge,
            ),
        )
        let furthestFuture = try LocationFix(
            position: ThrowCoreFixture.observer(),
            horizontalAccuracyMeters: 20,
            observedAt: ThrowCoreFixture.date.addingTimeInterval(
                LocationFixEvaluator.maximumFutureSkew,
            ),
        )

        #expect(LocationFixEvaluator.isValid(oldest, at: ThrowCoreFixture.date))
        #expect(LocationFixEvaluator.isValid(furthestFuture, at: ThrowCoreFixture.date))
    }

    @Test func fixAndDecisionDescriptionsRedactObserverLocation() throws {
        let coordinateSentinel = "27.123456"
        let fix = try LocationFix(
            position: ObserverPosition(
                coordinate: GeoCoordinate(latitude: 27.123456, longitude: -80.654321),
                altitude: Altitude(feet: 25),
            ),
            horizontalAccuracyMeters: 50,
            observedAt: ThrowCoreFixture.date,
        )
        let event = LocationEvent.fix(fix)
        let decision = LocationFixDecision.offerBest(fix)
        let renderings = [
            String(describing: fix),
            String(reflecting: fix),
            String(describing: event),
            String(reflecting: event),
            String(describing: decision),
            String(reflecting: decision),
        ]

        for rendering in renderings {
            #expect(rendering.contains(coordinateSentinel) == false)
        }
    }
}
