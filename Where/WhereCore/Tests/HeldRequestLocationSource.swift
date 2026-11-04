import Foundation
@testable import WhereCore

/// Delivers a one-shot result even after its caller cancels, like a queued system callback.
actor HeldRequestLocationSource: LocationSource {
    private let base = ScriptedLocationSource(authorizationStatus: .always)
    let gate = CompatibilityTestGate()
    private(set) var requests = 0
    private(set) var stops = 0

    nonisolated var sampleStream: AsyncStream<LocationSample> {
        base.sampleStream
    }

    nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        base.authorizationUpdates
    }

    func start() async {}
    func stop() async {
        stops += 1
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        requests += 1
        await gate.suspend()
        return .unavailable(.providerFailure)
    }
}
