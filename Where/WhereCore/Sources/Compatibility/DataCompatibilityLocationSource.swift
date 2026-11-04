import Foundation

/// Rejects new location work and late results after scope retirement. The underlying source
/// belongs only to this scope, so stopping its pending work cannot stop a replacement source.
actor DataCompatibilityLocationSource: LocationSource {
    private struct RequestID: Hashable { let rawValue = UUID() }
    private let base: any LocationSource
    private let access: DataCompatibilityAccess
    private var requests: [RequestID: Task<CurrentLocationResult, Never>] = [:]
    private var starts: [RequestID: Task<Void, Never>] = [:]

    init(base: any LocationSource, access: DataCompatibilityAccess) {
        self.base = base
        self.access = access
    }

    nonisolated var sampleStream: AsyncStream<LocationSample> {
        base.sampleStream
    }

    nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        base.authorizationUpdates
    }

    func start() async {
        guard !access.isRevoked else { return }
        let requestID = RequestID()
        let base = base
        let task = Task { await base.start() }
        starts[requestID] = task
        await task.value
        starts.removeValue(forKey: requestID)
        if access.isRevoked { await base.stop() }
    }

    func stop() async {
        await base.stop()
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        await base.currentAuthorization()
    }

    func requestPermission() async throws {
        try access.validate()
        try await base.requestPermission()
        try access.validate()
    }

    func requestCurrentLocation() async -> CurrentLocationResult {
        guard !access.isRevoked, !Task.isCancelled else { return .unavailable(.cancellation) }
        let requestID = RequestID()
        let base = base
        let task = Task { await base.requestCurrentLocation() }
        requests[requestID] = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        requests.removeValue(forKey: requestID)
        guard !access.isRevoked, !Task.isCancelled else { return .unavailable(.cancellation) }
        return result
    }

    func retire() async {
        access.revoke()
        let requests = Array(requests.values)
        let starts = Array(starts.values)
        for request in requests {
            request.cancel()
        }
        await base.stop()
        for start in starts {
            await start.value
        }
        for request in requests {
            _ = await request.value
        }
        await base.stop()
    }
}
