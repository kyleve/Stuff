/// Server-confirmed compatibility state. Revision is an opaque conditional-write token.
public struct SharedDataCompatibilityState: Hashable, Sendable {
    public struct Revision: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let accountID: DataCompatibilityAccountID
    public let requiredMajor: UInt
    public let revision: Revision

    public init(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        revision: Revision,
    ) {
        self.accountID = accountID
        self.requiredMajor = requiredMajor
        self.revision = revision
    }
}

/// Newness is established by shared inspection, not by a local store or a missing head alone.
public struct SharedDataCompatibilityVerification: Sendable {
    public enum History: Sendable {
        case newAccount
        case legacyAccount
        case existing(SharedDataCompatibilityState)
    }

    public let accountID: DataCompatibilityAccountID
    public let history: History

    public init(accountID: DataCompatibilityAccountID, history: History) {
        self.accountID = accountID
        self.history = history
    }
}

public protocol SharedDataCompatibilityTransport: Sendable {
    func accountID() async throws -> DataCompatibilityAccountID
    func verify(accountID: DataCompatibilityAccountID) async throws
        -> SharedDataCompatibilityVerification
    /// Reinspect before guarded creation. A concurrent creator's established state wins.
    func initialize(
        accountID: DataCompatibilityAccountID,
        newAccountMajor: UInt,
    ) async throws -> SharedDataCompatibilityState
    func advance(
        from expected: SharedDataCompatibilityState,
        to requiredMajor: UInt,
    ) async throws -> SharedDataCompatibilityState
    func accountChanges() -> AsyncStream<Void>
}
