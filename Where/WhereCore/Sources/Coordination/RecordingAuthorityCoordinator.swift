import Foundation

/// Reconciles server receipts into the existing store without owning another container.
public actor RecordingAuthorityCoordinator {
    private let store: any WhereStore
    private let transport: any RecordingAuthorityTransport

    public init(store: any WhereStore, transport: any RecordingAuthorityTransport) {
        self.store = store
        self.transport = transport
    }

    public nonisolated func updates() -> AsyncStream<Void> {
        store.changes()
    }

    public func observed() async throws -> RecordingAuthority {
        try await store.recordingAuthority()
    }

    public func deviceNames() async throws -> [RecordingDeviceID: String] {
        try await Dictionary(uniqueKeysWithValues: store.recordingDevices().map { (
            $0.id,
            $0.displayName,
        ) })
    }

    public func registerInstallation(_ context: InstallationRecordingContext) async throws {
        try await store.perform {
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

    @discardableResult
    public func refresh() async throws -> RecordingAuthority {
        guard let head = try await transport.current() else {
            guard try await store.recordingAuthority() == .initial else {
                throw RecordingAuthorityError.authorityDisappeared
            }
            return .initial
        }
        var receipts = [head]
        var cursor = head
        // Walk immutable parent links: a missed push must not lose a recovery exclusion.
        while let parent = cursor.proposal.expected.revision {
            try Task.checkCancellation()
            guard let receipt = try await transport.receipt(for: parent.eventID),
                  receipt.proposal.result == cursor.proposal.expected,
                  let sequence = cursor.proposal.result.revision?.sequence,
                  parent.sequence < sequence else { throw RecordingAuthorityError.invalidRecord }
            receipts.append(receipt)
            cursor = receipt
        }
        let verified = receipts.reversed().map(\.self)
        try await store.perform {
            for receipt in verified {
                try await self.store.addRecordingAuthorityCommit(receipt)
            }
        }
        return try await store.recordingAuthority()
    }

    /// Callers retain the same proposal across uncertain responses; never mint a replacement ID.
    @discardableResult
    public func submit(_ proposal: RecordingAuthorityProposal) async throws
        -> RecordingAuthorityCommit
    {
        let receipt = try await transport.commit(proposal)
        _ = try await refresh()
        return receipt
    }
}
