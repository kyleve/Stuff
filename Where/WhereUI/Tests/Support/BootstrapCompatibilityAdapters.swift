import Foundation
import WhereCore

@MainActor
final class BootstrapImportReadiness: CloudKitImportReadying {
    private(set) var isObserving = false
    private var imported = false
    func start() {
        isObserving = true
    }

    func recordImport() {
        if isObserving { imported = true }
    }

    func waitForImport() async -> Bool {
        imported
    }
}

/// Represents a monitoring registration left by the previous process.
actor BootstrapLocationSource: LocationSource {
    private(set) var stops = 0
    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }
    func start() async {}
    func stop() async {
        stops += 1
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        .unavailable(.timeout)
    }
}

actor BootstrapHeldAuthorizationSource: LocationSource {
    let hold: CompatibilityLaunchSuspension
    init(hold: CompatibilityLaunchSuspension) {
        self.hold = hold
    }

    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }
    func start() async {}
    func stop() async {}
    func currentAuthorization() async -> LocationAuthorizationStatus {
        await hold.suspend()
        return .always
    }

    func requestPermission() async throws {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        .unavailable(.timeout)
    }
}
