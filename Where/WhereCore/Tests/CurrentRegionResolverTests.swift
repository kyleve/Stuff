import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct CurrentRegionResolverTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10000)

    @Test func freshConfidentFixResolvesTrackedRegion() async throws {
        let services = try await authorizedServices(sample: sample())

        #expect(await services.currentRegion.resolve(now: now) == .resolved(.california))
    }

    @Test func exactlyOneKilometerIsAccepted() async throws {
        let services = try await authorizedServices(
            sample: sample(accuracy: 1000),
            boundaryDistance: 1001,
        )

        #expect(await services.currentRegion.resolve(now: now) == .resolved(.california))
    }

    @Test func accuracyAboveOneKilometerIsRejected() async throws {
        let services = try await authorizedServices(sample: sample(accuracy: 1001))

        #expect(
            await services.currentRegion.resolve(now: now)
                == .unavailable(.excessiveUncertainty),
        )
    }

    @Test func negativeAccuracyIsInvalid() async throws {
        let services = try await authorizedServices(sample: sample(accuracy: -1))

        #expect(await services.currentRegion.resolve(now: now) == .unavailable(.invalidFix))
    }

    @Test func fixOlderThanSixtySecondsIsStale() async throws {
        let services = try await authorizedServices(
            sample: sample(timestamp: now.addingTimeInterval(-61)),
        )

        #expect(await services.currentRegion.resolve(now: now) == .unavailable(.staleFix))
    }

    @Test func fixExactlySixtySecondsOldIsAccepted() async throws {
        let services = try await authorizedServices(
            sample: sample(timestamp: now.addingTimeInterval(-60)),
        )

        #expect(await services.currentRegion.resolve(now: now) == .resolved(.california))
    }

    @Test func uncertaintyThatReachesBoundaryIsRejected() async throws {
        let services = try await authorizedServices(
            sample: sample(accuracy: 500),
            boundaryDistance: 500,
        )

        #expect(
            await services.currentRegion.resolve(now: now)
                == .unavailable(.boundaryUncertainty),
        )
    }

    @Test func locationOutsideTrackedRegionsIsRejected() async throws {
        let services = try await authorizedServices(sample: sample(), region: .other)

        #expect(
            await services.currentRegion.resolve(now: now)
                == .unavailable(.outsideTrackedRegions),
        )
    }

    @Test(
        arguments: [
            CurrentLocationResult.UnavailableReason.preciseLocationDisabled,
            .providerFailure,
            .timeout,
            .cancellation,
            .authorizationUnavailable(.denied),
        ],
    )
    func locationFailureIsPreserved(
        reason: CurrentLocationResult.UnavailableReason,
    ) async throws {
        let services = try await authorizedServices(result: .unavailable(reason))

        #expect(
            await services.currentRegion.resolve(now: now)
                == .unavailable(.location(reason)),
        )
    }

    @Test func inactiveRecordingDoesNotRequestAWelcomeRegion() async throws {
        let source = ScriptedLocationSource()
        source.setNextRequestedLocation(sample())
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            attributor: FixedRegionAttributor(),
        )

        #expect(
            await services.currentRegion.resolve(now: now)
                == .unavailable(.recordingInactive),
        )
    }

    @Test func authorizationRevokedDuringFixRequestDoesNotResolveARegion() async throws {
        let source = GatedWelcomeLocationSource()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            attributor: FixedRegionAttributor(),
        )
        try await services.ingestor.authorizeRecording()
        let resolution = Task { await services.currentRegion.resolve(now: now) }
        await source.waitUntilRequested()

        await services.ingestor.revokeRecordingAuthorization()
        await source.resolve(with: .success(sample()))

        #expect(await resolution.value == .unavailable(.recordingInactive))
    }

    private func authorizedServices(
        sample: LocationSample,
        boundaryDistance: Double = 10000,
        region: Region = .california,
    ) async throws -> WhereServices {
        try await authorizedServices(
            result: .success(sample),
            boundaryDistance: boundaryDistance,
            region: region,
        )
    }

    private func authorizedServices(
        result: CurrentLocationResult,
        boundaryDistance: Double = 10000,
        region: Region = .california,
    ) async throws -> WhereServices {
        let source = ScriptedLocationSource()
        source.setNextRequestedLocationResult(result)
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            attributor: FixedRegionAttributor(
                region: region,
                boundaryDistance: boundaryDistance,
            ),
        )
        try await services.ingestor.authorizeRecording()
        return services
    }

    private func sample(
        timestamp: Date? = nil,
        accuracy: Double = 5,
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp ?? now,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: accuracy,
            source: .gpsSignificantChange,
        )
    }
}

private struct FixedRegionAttributor: RegionAttributing {
    let region: Region
    let boundaryDistance: Double?

    init(region: Region = .california, boundaryDistance: Double? = 10000) {
        self.region = region
        self.boundaryDistance = boundaryDistance
    }

    var loadedRegions: [Region] {
        region == .other ? [] : [region]
    }

    func region(at _: Coordinate) -> Region {
        region
    }

    func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
        boundaryDistance
    }
}

private actor GatedWelcomeLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }

    private var requestContinuation: CheckedContinuation<CurrentLocationResult, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var didRequest = false

    func start() async {}
    func stop() async {}

    func requestCurrentLocation() async -> CurrentLocationResult {
        didRequest = true
        for waiter in requestWaiters {
            waiter.resume()
        }
        requestWaiters.removeAll()
        return await withCheckedContinuation { requestContinuation = $0 }
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}

    func waitUntilRequested() async {
        guard didRequest == false else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resolve(with result: CurrentLocationResult) {
        requestContinuation?.resume(returning: result)
        requestContinuation = nil
    }
}
