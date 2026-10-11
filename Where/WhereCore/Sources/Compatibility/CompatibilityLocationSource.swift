import Foundation

/// Owns one normal world's GPS work. Revocation is permanent even if old callers try to restart it.
actor CompatibilityLocationSource: LocationSource {
    private let base: any LocationSource
    private let store: any WhereStore
    private var retired = false
    private var requests: [UUID: Task<CurrentLocationResult, Never>] = [:]

    init(base: any LocationSource, store: any WhereStore) {
        self.base = base; self.store = store
    }

    nonisolated var sampleStream: AsyncStream<LocationSample> {
        base.sampleStream
    }

    nonisolated var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        base.authorizationUpdates
    }

    private func validate() async throws {
        guard !retired else { throw DataCompatibilityError.accessRevoked }
        try await store.validateDataAccess()
        guard !retired else { throw DataCompatibilityError.accessRevoked }
    }

    func start() async {
        do {
            try await validate()
            await base.start()
            try await validate()
        } catch {
            await retire()
            log(error)
        }
    }

    func stop() async {
        await base.stop()
    }

    func currentAuthorization() async -> LocationAuthorizationStatus {
        await base
            .currentAuthorization()
    }

    func requestPermission() async throws {
        try await validate()
        try await base.requestPermission()
        try await validate()
    }

    func requestCurrentLocation() async -> CurrentLocationResult {
        do { try await validate() }
        catch { log(error); return .unavailable(.cancellation) }
        let requestID = UUID()
        let task = Task { await base.requestCurrentLocation() }
        requests[requestID] = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: {
            task.cancel()
        }
        requests.removeValue(forKey: requestID)
        do { try await validate() }
        catch { log(error); return .unavailable(.cancellation) }
        return result
    }

    func retire() async {
        retired = true
        let pending = Array(requests.values)
        for request in pending {
            request.cancel()
        }
        await base.stop()
        // CoreLocation's cancellation handler finishes every waiter and stops one-shot hardware.
        for request in pending {
            _ = await request.value
        }
    }

    private func log(_ error: any Error) {
        WhereLog.root(DataCompatibilityLog.self)(attachments: [.error(
            error,
            name: "location-access-error",
        )]) {
            .accessBlocked(description: error.localizedDescription)
        }
    }
}
