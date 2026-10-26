import Foundation

/// The boundary that serializes authority changes and resolves uncertain write outcomes.
///
/// A new proposal must match the current server state. An identical retry returns its original
/// receipt even if the head advanced. Reusing an event ID for different content is a conflict.
/// Consumers use `RecordingAuthorityCoordinator` to reconcile receipts into the existing store.
public protocol RecordingAuthorityTransport: Sendable {
    /// Returns the receipt named by the current head, or nil for an absent head. Failures throw.
    func current() async throws -> RecordingAuthorityCommit?
    /// Finds a committed transition by identity without requiring it to remain the current head.
    func receipt(for eventID: RecordingAuthority.EventID) async throws -> RecordingAuthorityCommit?
    /// Conditionally saves a new transition or returns the receipt from an earlier attempt.
    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit
}

/// Local development/demo authority, with the same conflict and retry semantics as CloudKit.
public actor LocalRecordingAuthorityTransport: RecordingAuthorityTransport {
    private var latest: RecordingAuthorityCommit?
    private var receipts: [RecordingAuthority.EventID: RecordingAuthorityCommit] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    public func current() -> RecordingAuthorityCommit? {
        latest
    }

    public func receipt(for eventID: RecordingAuthority
        .EventID) -> RecordingAuthorityCommit?
    {
        receipts[eventID]
    }

    public func commit(_ proposal: RecordingAuthorityProposal) throws -> RecordingAuthorityCommit {
        try proposal.validate()
        guard let eventID = proposal.result.revision?.eventID
        else { throw RecordingAuthorityError.invalidRecord }
        if let receipt = receipts[eventID] {
            guard receipt.proposal == proposal else { throw RecordingAuthorityError.conflict }
            return receipt
        }
        guard (latest?.proposal.result ?? .initial) == proposal.expected
        else { throw RecordingAuthorityError.conflict }
        let receipt = RecordingAuthorityCommit(proposal: proposal, committedAt: now())
        receipts[eventID] = receipt
        latest = receipt
        return receipt
    }
}
