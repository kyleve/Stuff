import Foundation

/// All authority mutations use compare-and-save against server state.
public protocol RecordingAuthorityTransport: Sendable {
    func current() async throws -> RecordingAuthorityCommit?
    func receipt(for eventID: RecordingAuthority.EventID) async throws -> RecordingAuthorityCommit?
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
