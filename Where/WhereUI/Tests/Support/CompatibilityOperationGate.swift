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

/// Holds account verification without holding teardown or the local authority projection.
actor CompatibilityAccountTransport: RecordingAuthorityTransport {
    private let base = LocalRecordingAuthorityTransport(now: { .now })
    private var gate: CompatibilityOperationGate?
    func holdIdentity(_ gate: CompatibilityOperationGate) {
        self.gate = gate
    }

    func accountID() async -> RecordingAccountID {
        if let gate { self.gate = nil; await gate.wait() }
        return .local
    }

    func subscribe() {}
    func current() async -> RecordingAuthorityCommit? {
        await base.current()
    }

    func fetchCommit(for eventID: RecordingAuthority.EventID) async -> RecordingAuthorityCommit? {
        await base.fetchCommit(for: eventID)
    }

    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit {
        try await base.commit(proposal)
    }
}
