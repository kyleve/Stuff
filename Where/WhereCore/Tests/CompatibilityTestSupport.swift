import CloudKit
@_spi(Testing) @testable import WhereCore

actor CompatibilityTestTransport: RecordingAuthorityTransport {
    enum Availability { case online, offline, signedOut }
    private let base = LocalRecordingAuthorityTransport(now: { .now })
    private(set) var readCount = 0
    private var nextReadGate: CompatibilityTestGate?
    func holdNextRead(_ gate: CompatibilityTestGate) {
        nextReadGate = gate
    }

    private var availability: Availability = .online
    func setAvailability(_ value: Availability) {
        availability = value
    }

    private func check() throws {
        switch availability {
            case .online: return
            case .offline: throw CKError(.networkUnavailable)
            case .signedOut: throw CKError(.notAuthenticated)
        }
    }

    func subscribe() throws {
        try check()
    }

    func current() async throws -> RecordingAuthorityCommit? {
        readCount += 1
        try check()
        let value = await base.current()
        if let gate = nextReadGate {
            nextReadGate = nil
            await gate.suspend()
        }
        return value
    }

    func fetchCommit(for eventID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityCommit?
    {
        try check()
        return await base.fetchCommit(for: eventID)
    }

    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit {
        try check()
        return try await base.commit(proposal)
    }
}

/// Server changes that a local-only history inspection cannot observe.
enum CompatibilityRemoteChange {
    case signedOut, newerRequirement
}

func waitForCompatibilityChecks(
    _ count: Int,
    in coordinator: DataCompatibilityCoordinator,
) async throws {
    struct TimedOut: Error {}
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while await coordinator.pendingCheckCountForTesting != count {
        guard clock.now < deadline else { throw TimedOut() }
        await Task.yield()
    }
}
