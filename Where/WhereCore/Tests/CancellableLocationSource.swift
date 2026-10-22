import Foundation
import WhereCore

/// Holds a one-shot request until cancellation, like the platform location adapter.
actor CancellableLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { _ in }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { _ in }
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var requested = false
    private(set) var cancelled = false
    func start() {
        starts += 1
    }

    func stop() {
        stops += 1
    }

    func currentAuthorization() -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        requested = true
        do { try await Task.sleep(for: .seconds(60)) }
        catch { cancelled = true }
        return .unavailable(.cancellation)
    }
}
