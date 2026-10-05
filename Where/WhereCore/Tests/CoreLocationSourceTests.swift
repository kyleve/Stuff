import CoreLocation
import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct CoreLocationSourceTests {
    @Test func retainsValidSpeedAndAltitudeWithTheirAccuracies() {
        let location = Self.location(
            speed: 240,
            speedAccuracy: 2,
            altitude: 11000,
            verticalAccuracy: 8,
        )
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 2),
            altitude: .init(meters: 11000, accuracyMeters: 8),
        ))
    }

    @Test func invalidSpeedDoesNotDiscardValidBelowSeaLevelAltitude() {
        let location = Self.location(
            speed: -1,
            speedAccuracy: -1,
            altitude: -30,
            verticalAccuracy: 3,
        )
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: nil,
            altitude: .init(meters: -30, accuracyMeters: 3),
        ))
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity])
    func unavailableOrNonfiniteMeasurementsStayAbsent(_ invalid: Double) {
        let location = Self.location(
            speed: 220,
            speedAccuracy: invalid,
            altitude: 10000,
            verticalAccuracy: invalid,
        )
        #expect(CoreLocationSource.motion(from: location) == nil)
    }

    @Test func nonfiniteValuesStayAbsentEvenWithValidAccuracies() {
        let location = Self.location(
            speed: .infinity,
            speedAccuracy: 1,
            altitude: .nan,
            verticalAccuracy: 1,
        )
        #expect(CoreLocationSource.motion(from: location) == nil)
    }

    @Test func zeroSpeedAccuracyIsValidButZeroVerticalAccuracyIsUnavailable() {
        let location = Self.location(speed: 0, speedAccuracy: 0, altitude: 100, verticalAccuracy: 0)
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: .init(metersPerSecond: 0, accuracyMetersPerSecond: 0),
            altitude: nil,
        ))
    }

    private static func location(
        speed: Double,
        speedAccuracy: Double,
        altitude: Double,
        verticalAccuracy: Double,
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -100),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy,
            course: 90,
            courseAccuracy: 1,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: Date(timeIntervalSince1970: 1000),
        )
    }

    @Test func reducedPrecisionReturnsAnExplicitFailureWithoutRequesting() async {
        let (source, probe) = configuredSource(hasPreciseLocation: false)

        #expect(
            await source.requestCurrentLocation() == .unavailable(.preciseLocationDisabled),
        )
        #expect(probe.requestCount == 0)
    }

    @Test func deniedAuthorizationReturnsAnExplicitFailureWithoutRequesting() async {
        let (source, probe) = configuredSource(authorization: .denied)

        #expect(
            await source.requestCurrentLocation()
                == .unavailable(.authorizationUnavailable(.denied)),
        )
        #expect(probe.requestCount == 0)
    }

    @Test func staleCachedCallbackDoesNotSatisfyPendingRequest() async {
        let (source, probe) = configuredSource()
        let request = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 1 }
        let stale = sample(timestamp: Date().addingTimeInterval(-61))
        let fresh = sample()

        source.deliverCurrentLocationsForTesting([stale])
        source.deliverCurrentLocationsForTesting([fresh])

        #expect(await request.value == .success(fresh))
    }

    @Test func negativeAccuracyCallbackDoesNotSatisfyPendingRequest() async {
        let (source, probe) = configuredSource()
        let request = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 1 }
        let invalid = sample(accuracy: -1)
        let valid = sample()

        source.deliverCurrentLocationsForTesting([invalid])
        source.deliverCurrentLocationsForTesting([valid])

        #expect(await request.value == .success(valid))
    }

    @Test func providerFailureHasAnExplicitOutcome() async {
        let (source, probe) = configuredSource()
        let request = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 1 }

        source.failCurrentLocationForTesting()

        #expect(await request.value == .unavailable(.providerFailure))
    }

    @Test func boundedRequestTimesOutAndStopsTheUnderlyingRequest() async {
        let (source, probe) = configuredSource(timeout: .milliseconds(1))

        #expect(await source.requestCurrentLocation() == .unavailable(.timeout))
        #expect(probe.requestCount == 1)
        #expect(probe.stopCount == 1)
    }

    @Test func concurrentWaitersCoalesceAndCancellationRemovesOnlyOne() async {
        let (source, probe) = configuredSource()
        let first = Task { await source.requestCurrentLocation() }
        let second = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 1 }

        first.cancel()
        #expect(await first.value == .unavailable(.cancellation))
        #expect(probe.stopCount == 0)

        let fix = sample()
        source.deliverCurrentLocationsForTesting([fix])

        #expect(await second.value == .success(fix))
        #expect(probe.requestCount == 1)
    }

    @Test func cancellingTheLastWaiterStopsAndClearsTheRequest() async {
        let (source, probe) = configuredSource()
        let first = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 1 }

        first.cancel()
        #expect(await first.value == .unavailable(.cancellation))
        #expect(probe.stopCount == 1)

        source.deliverCurrentLocationsForTesting([sample()])
        let second = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 2 }
        let fresh = sample()
        source.deliverCurrentLocationsForTesting([fresh])

        #expect(await second.value == .success(fresh))
    }

    @Test func timedOutRequestCanStartAnotherRequest() async {
        let (source, probe) = configuredSource(timeout: .milliseconds(1))
        #expect(await source.requestCurrentLocation() == .unavailable(.timeout))
        #expect(probe.stopCount == 1)

        probe.timeout = .seconds(10)
        let retry = Task { await source.requestCurrentLocation() }
        await waitUntil { probe.requestCount == 2 }
        let fix = sample()
        source.deliverCurrentLocationsForTesting([fix])

        #expect(await retry.value == .success(fix))
    }

    @Test func synchronousDriverCallbackCompletesTheRequest() async {
        let (source, probe) = configuredSource(timeout: .milliseconds(1))
        let fix = sample()
        probe.onRequest = { source.deliverCurrentLocationsForTesting([fix]) }

        #expect(await source.requestCurrentLocation() == .success(fix))
        #expect(probe.stopCount == 0)
    }

    private func configuredSource(
        authorization: LocationAuthorizationStatus = .always,
        hasPreciseLocation: Bool = true,
        timeout: Duration = .seconds(10),
    ) -> (CoreLocationSource, LocationRequestProbe) {
        let source = CoreLocationSource()
        let probe = LocationRequestProbe(
            authorization: authorization,
            hasPreciseLocation: hasPreciseLocation,
            timeout: timeout,
        )
        source.configureCurrentLocationForTesting(driver: probe)
        return (source, probe)
    }

    private func sample(
        timestamp: Date = Date(),
        accuracy: Double = 5,
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
            horizontalAccuracy: accuracy,
            source: .gpsSignificantChange,
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        while condition() == false {
            await Task.yield()
        }
    }
}

@MainActor
private final class LocationRequestProbe: CurrentLocationRequestDriving {
    let authorization: LocationAuthorizationStatus
    let hasPreciseLocation: Bool
    var timeout: Duration
    var requestCount = 0
    var stopCount = 0
    var onRequest: (() -> Void)?

    init(
        authorization: LocationAuthorizationStatus,
        hasPreciseLocation: Bool,
        timeout: Duration,
    ) {
        self.authorization = authorization
        self.hasPreciseLocation = hasPreciseLocation
        self.timeout = timeout
    }

    func requestLocation() {
        requestCount += 1
        onRequest?()
    }

    func stopLocation() {
        stopCount += 1
    }
}
