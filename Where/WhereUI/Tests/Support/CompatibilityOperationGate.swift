import WhereCore

/// A dependency that reports cancellation but returns only when explicitly released.
@MainActor
final class CompatibilityOperationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var entered = false
    private(set) var cancelled = false

    func wait() async {
        guard !released else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation = $0
                entered = true
            }
        } onCancel: {
            Task { @MainActor in self.cancelled = true }
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

/// Suspends onboarding after scope activation, before it can configure recording.
actor CompatibilityGatedLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { $0.finish() }
    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> { $0.finish() }
    let authorization: CompatibilityOperationGate

    init(authorization: CompatibilityOperationGate) {
        self.authorization = authorization
    }

    func start() async {}
    func stop() async {}
    func requestPermission() async throws {}
    func requestCurrentLocation() async -> CurrentLocationResult {
        .unavailable(.timeout)
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        await authorization.wait()
        return .always
    }
}
