import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore

@MainActor
struct CoreLocationSourceTests {
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
    let timeout: Duration
    var requestCount = 0
    var stopCount = 0

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
    }

    func stopLocation() {
        stopCount += 1
    }
}
