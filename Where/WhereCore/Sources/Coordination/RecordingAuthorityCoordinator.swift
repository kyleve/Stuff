import Foundation

/// Reconciles server receipts into the existing store without owning another container.
public actor RecordingAuthorityCoordinator {
    private let store: any WhereStore
    private let transport: any RecordingAuthorityTransport

    public init(store: any WhereStore, transport: any RecordingAuthorityTransport) {
        self.store = store
        self.transport = transport
    }

    public func observed() async throws -> RecordingAuthority {
        try await store.recordingAuthority()
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
