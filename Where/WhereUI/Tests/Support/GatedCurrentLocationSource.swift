import WhereCore

/// Location source that lets a test resolve overlapping one-shot requests in
/// any order without relying on timing.
actor GatedCurrentLocationSource: LocationSource {
    nonisolated let sampleStream = AsyncStream<LocationSample> { continuation in
        continuation.finish()
    }

    nonisolated let authorizationUpdates = AsyncStream<LocationAuthorizationStatus> {
        continuation in
        continuation.finish()
    }

    private var requests: [CheckedContinuation<LocationSample?, Never>] = []
    private var requestCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func start() async {}
    func stop() async {}

    func requestCurrentLocation() async -> LocationSample? {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            let count = requests.count
            requestCountWaiters.removeValue(forKey: count)?.forEach { $0.resume() }
        }
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}

    func waitUntilRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters[count, default: []].append(continuation)
        }
    }

    func resolveRequest(at index: Int, with sample: LocationSample?) {
        requests.remove(at: index).resume(returning: sample)
    }
}
