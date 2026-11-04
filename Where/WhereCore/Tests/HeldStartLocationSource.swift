import Foundation
@testable import WhereCore

/// Accepts a physical start only when released, even if stop was requested meanwhile.
actor HeldStartLocationSource: LocationSource {
    private let base = ScriptedLocationSource(authorizationStatus: .always)
    let startGate = CompatibilityTestGate()
    private(set) var isMonitoring = false
    private(set) var stops = 0

    nonisolated var sampleStream: AsyncStream<LocationSample> {
        base.sampleStream
    }

    nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        base.authorizationUpdates
    }

    func start() async {
        await startGate.suspend()
        isMonitoring = true
    }

    func stop() async {
        stops += 1
        isMonitoring = false
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        .unavailable(.cancellation)
    }
}
