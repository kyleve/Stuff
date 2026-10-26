import CloudKit
import Foundation

/// Reconciles the server's immutable authority history into an injected store.
///
/// Transport writes and local projection writes are separate transactions. A server commit can
/// succeed before reconciliation fails, so callers retain proposals until their outcomes are known.
/// This actor does not own GPS, recording consent, refresh scheduling, or another store container.
public actor RecordingAuthorityCoordinator {
    private let store: any WhereStore
    private let transport: any RecordingAuthorityTransport

    private let account: RecordingAccountAccess

    public init(
        store: any WhereStore,
        transport: any RecordingAuthorityTransport,
        installation: any InstallationRecordingContextStoring,
    ) {
        self.store = store
        self.transport = transport
        account = RecordingAccountAccess(installation: installation, transport: transport)
    }

    func withAccountAccess<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
    ) async throws -> T {
        try Task.checkCancellation()
        try DataAccessPermit.current?.validate()
        let session = try await account.verify()
        return try await session.withAccess(operation)
    }

    public func invalidateAccount() async throws {
        try await account.invalidate()
    }

    public func subscribe() async throws {
        try await transport.subscribe()
    }

    public nonisolated func updates() -> AsyncStream<Void> {
        store.changes()
    }

    /// Reads the local commit projection without a network request or a freshness guarantee.
    public func observed() async throws -> RecordingAuthority {
        let session = try await account.cachedSession()
        return try await session.withAccess { try await self.store.recordingAuthority() }
    }

    public func deviceNames() async throws -> [RecordingDeviceID: String] {
        try await Dictionary(uniqueKeysWithValues: store.recordingDevices().map { (
            $0.id,
            $0.displayName,
        ) })
    }

    public func registerInstallation(_ context: InstallationRecordingContext) async throws {
        try await store.perform {
            guard try await self.store.recordingDeviceRemovals()
                .contains(where: { $0.deviceID == context.currentDevice.id }) == false
            else { throw RecordingPersistenceError.currentDeviceRemoved(context.currentDevice.id) }
            if try await self.store.recordingDeviceProfiles()
                .contains(where: { $0.id == context.currentDevice.id }) { return }
            let generation = try await self.store.dataGeneration()
            try await self.store.addRecordingDeviceProfile(.init(
                id: context.currentDevice.id,
                systemName: context.currentDevice.systemName,
                kind: context.currentDevice.kind,
                registeredAt: context.registeredAt,
                registrationGenerationID: generation.id,
            ))
        }
    }

    func requireEligibleHandoffTarget(_ deviceID: RecordingDeviceID) async throws {
        guard try await store.recordingDeviceRemovals()
            .contains(where: { $0.deviceID == deviceID }) == false
        else { throw RecordingAuthorityError.invalidHandoff }
    }

    /// Fetches the head and every predecessor before adding commits in one local transaction.
    /// Missing or inconsistent history throws. Existing local commits remain, so a stale head
    /// cannot overwrite newer authority already observed by the store.
    @discardableResult
    public func refresh() async throws -> RecordingAuthority {
        try Task.checkCancellation()
        try DataAccessPermit.current?.validate()
        let session = try await account.verify()
        do {
            let result = try await session.withAccess { try await self.refreshVerified() }
            try await account.acceptAuthority(using: session)
            return result
        } catch {
            if (error as? CKError)?.code == .notAuthenticated {
                try await account.rejectAuthority(using: session)
            }
            throw error
        }
    }

    private func refreshVerified() async throws -> RecordingAuthority {
        try DataAccessPermit.current?.validate()
        guard let head = try await transport.current() else {
            // An absent head is valid only while local history is empty.
            // Established authority cannot disappear and enable another initial claim.
            guard try await store.recordingAuthority() == .initial else {
                throw RecordingAuthorityError.authorityDisappeared
            }
            return .initial
        }
        var commits = [head]
        var cursor = head
        // A later head can hide a recovery while this device was offline. Follow every parent to
        // retain its history choice, and require each edge to reproduce the expected state exactly.
        while let parent = cursor.proposal.expected.revision {
            try Task.checkCancellation()
            guard let commit = try await transport.fetchCommit(for: parent.eventID),
                  commit.proposal.result.authority == cursor.proposal.expected,
                  parent.sequence < cursor.proposal.result.revision.sequence
            else { throw RecordingAuthorityError.invalidRecord }
            commits.append(commit)
            cursor = commit
        }
        try DataAccessPermit.current?.validate()
        let verified = commits.reversed().map(\.self)
        // An unchanged refresh must not emit a store change that triggers another refresh.
        let existing = try await store.recordingAuthorityCommits()
        if verified.allSatisfy(existing.contains) { return try await store.recordingAuthority() }
        try await store.perform {
            for commit in verified {
                try await self.store.addRecordingAuthorityCommit(commit)
            }
        }
        return try await store.recordingAuthority()
    }

    /// Commits a proposal and refreshes local authority before returning its original commit.
    ///
    /// A returned commit can describe an older transition than the refreshed authority. A thrown
    /// error can occur after the server committed. Retry the same proposal to resolve that outcome.
    @discardableResult
    public func submit(_ proposal: RecordingAuthorityProposal) async throws
        -> RecordingAuthorityCommit
    {
        try Task.checkCancellation()
        try DataAccessPermit.current?.validate()
        let session = try await account.verify()
        return try await session.withAccess {
            let commit = try await self.transport.commit(proposal)
            try session.validate()
            _ = try await self.refreshVerified()
            try await self.account.acceptAuthority(using: session)
            return commit
        }
    }
}
