import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct CurrentRegionResolverTests {
    @Test func resolvesTrackedRegionWhileRecordingIsAuthorized() async throws {
        let (services, source) = try makeServices()
        source.setNextRequestedLocation(sample(latitude: 37.7749, longitude: -122.4194))
        try await services.ingestor.authorizeRecording()

        #expect(await services.currentRegion.resolve() == .california)
    }

    @Test func inactiveRecordingDoesNotRequestAWelcomeRegion() async throws {
        let (services, source) = try makeServices()
        source.setNextRequestedLocation(sample(latitude: 37.7749, longitude: -122.4194))

        #expect(await services.currentRegion.resolve() == nil)
    }

    @Test func missingFixDoesNotResolveAWelcomeRegion() async throws {
        let (services, _) = try makeServices()
        try await services.ingestor.authorizeRecording()

        #expect(await services.currentRegion.resolve() == nil)
    }

    @Test func locationOutsideTrackedRegionsDoesNotResolveAWelcomeRegion() async throws {
        let (services, source) = try makeServices(
            attributor: RegionAttributor(for: [.california]),
        )
        source.setNextRequestedLocation(sample(latitude: 40.7128, longitude: -74.0060))
        try await services.ingestor.authorizeRecording()

        #expect(await services.currentRegion.resolve() == nil)
    }

    @Test func authorizationRevokedDuringFixRequestDoesNotResolveAWelcomeRegion() async throws {
        let source = GatedWelcomeLocationSource()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
        )
        try await services.ingestor.authorizeRecording()
        let resolution = Task { await services.currentRegion.resolve() }
        await source.waitUntilRequested()

        await services.ingestor.revokeRecordingAuthorization()
        await source.resolve(with: sample(latitude: 37.7749, longitude: -122.4194))

        #expect(await resolution.value == nil)
    }

    private func makeServices(
        attributor: any RegionAttributing = RegionAttributor.shared,
    ) throws -> (WhereServices, ScriptedLocationSource) {
        let source = ScriptedLocationSource()
        return try (
            WhereServices(
                store: SwiftDataStore.inMemory(),
                locationSource: source,
                attributor: attributor,
            ),
            source,
        )
    }

    private func sample(latitude: Double, longitude: Double) -> LocationSample {
        LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }
}

private actor GatedWelcomeLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }

    private var requestContinuation: CheckedContinuation<LocationSample?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var didRequest = false

    func start() async {}
    func stop() async {}

    func requestCurrentLocation() async -> LocationSample? {
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

    func resolve(with sample: LocationSample?) {
        requestContinuation?.resume(returning: sample)
        requestContinuation = nil
    }
}
