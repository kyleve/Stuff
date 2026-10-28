import Foundation

/// The boundary that serializes authority changes and resolves uncertain write outcomes.
///
/// A new proposal must match the current server state. An identical retry returns its original
/// commit even if the head advanced. Reusing an event ID for different content is a conflict.
/// Consumers use `RecordingAuthorityCoordinator` to reconcile commits into the existing store.
public protocol RecordingAuthorityTransport: Sendable {
    func accountID() async throws -> RecordingAccountID
    func subscribe() async throws
    /// Returns the commit named by the current head, or nil for an absent head. Failures throw.
    func current() async throws -> RecordingAuthorityCommit?
    /// Finds a committed transition by identity without requiring it to remain the current head.
    func fetchCommit(for eventID: RecordingAuthority.EventID) async throws
        -> RecordingAuthorityCommit?
    /// Conditionally saves a new transition or returns the commit from an earlier attempt.
    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit
}

/// Local development/demo authority, with the same conflict and retry semantics as CloudKit.
public actor LocalRecordingAuthorityTransport: RecordingAuthorityTransport {
    private var latest: RecordingAuthorityCommit?
    private var commits: [RecordingAuthority.EventID: RecordingAuthorityCommit] = [:]
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
        for commit in commits
            .sorted(by: {
                ($0.proposal.result.revision?.sequence ?? 0) <
                    ($1.proposal.result.revision?.sequence ?? 0)
            })
        {
            try commit.proposal.validate()
            guard commit.proposal.expected == state,
                  let eventID = commit.proposal.result.revision?.eventID
            else { throw RecordingAuthorityError.invalidRecord }
            self.commits[eventID] = commit
            latest = commit
            state = commit.proposal.result
        }
    }

    public func accountID() -> RecordingAccountID {
        .local
    }

    public func subscribe() {}

    public func current() -> RecordingAuthorityCommit? {
        latest
    }

    public func fetchCommit(for eventID: RecordingAuthority
        .EventID) -> RecordingAuthorityCommit?
    {
        commits[eventID]
    }

    public func commit(_ proposal: RecordingAuthorityProposal) throws -> RecordingAuthorityCommit {
        try proposal.validate()
        guard let eventID = proposal.result.revision?.eventID
        else { throw RecordingAuthorityError.invalidRecord }
        if let commit = commits[eventID] {
            guard commit.proposal == proposal else { throw RecordingAuthorityError.conflict }
            return commit
        }
        guard (latest?.proposal.result ?? .initial) == proposal.expected
        else { throw RecordingAuthorityError.conflict }
        let commit = RecordingAuthorityCommit(proposal: proposal, committedAt: now())
        commits[eventID] = commit
        latest = commit
        return commit
    }
}

/// The host selects CloudKit only for audiences whose domain store syncs to iCloud.
public enum RecordingAuthorityEnvironment: Sendable {
    case local
    case cloudKit(containerIdentifier: String)
}
