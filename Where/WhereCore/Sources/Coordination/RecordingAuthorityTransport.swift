import Foundation

/// All authority mutations use compare-and-save against server state.
public protocol RecordingAuthorityTransport: Sendable {
    func subscribe() async throws
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

    public init(
        restoring commits: [RecordingAuthorityCommit],
        now: @escaping @Sendable () -> Date,
    ) throws {
        self.now = now
        var state = RecordingAuthority.initial
        for receipt in commits
            .sorted(by: {
                ($0.proposal.result.revision?.sequence ?? 0) <
                    ($1.proposal.result.revision?.sequence ?? 0)
            })
        {
            try receipt.proposal.validate()
            guard receipt.proposal.expected == state,
                  let eventID = receipt.proposal.result.revision?.eventID
            else { throw RecordingAuthorityError.invalidRecord }
            receipts[eventID] = receipt
            latest = receipt
            state = receipt.proposal.result
        }
    }

    public func subscribe() {}

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

/// The host selects CloudKit only for audiences whose domain store syncs to iCloud.
public enum RecordingAuthorityEnvironment: Sendable {
    case local
    case cloudKit(containerIdentifier: String)
}
