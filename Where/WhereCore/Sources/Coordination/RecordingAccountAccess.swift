import Foundation

/// Binds one local projection to its original account and fences suspended work on invalidation.
/// Identity must be checked once per process before any offline fallback is allowed.
@MainActor
final class RecordingAccountAccess {
    private enum Session {
        case unverified(DataAccessPermit)
        case identified(RecordingAccountID, DataAccessPermit)
        case verified(RecordingAccountID, DataAccessPermit)

        var permit: DataAccessPermit {
            switch self {
                case let .unverified(permit), let .identified(_, permit),
                     let .verified(_, permit): permit
            }
        }
    }

    private let installation: any InstallationRecordingContextStoring
    private let transport: any RecordingAuthorityTransport
    private var session = Session.unverified(DataAccessPermit())

    nonisolated init(
        installation: any InstallationRecordingContextStoring,
        transport: any RecordingAuthorityTransport,
    ) {
        self.installation = installation
        self.transport = transport
    }

    func invalidate() throws {
        session.permit.revoke()
        session = .unverified(DataAccessPermit())
        let binding = try installation.resolve().recordingAccount
        try installation.setRecordingAccount(.invalidated(binding?.accountID))
    }

    func verify() async throws -> DataAccessPermit {
        let permit = session.permit
        // Nested reads/submissions stay inside the account already verified by the role operation.
        if DataAccessPermit.current === permit {
            try permit.validate()
            return permit
        }
        let accountID: RecordingAccountID
        do { accountID = try await transport.accountID() }
        catch {
            // Authentication failure must not become an offline success on the next retry.
            if !CloudKitRecordingAuthorityTransport.isTemporarilyUnavailable(error),
               session.permit === permit
            {
                try invalidate()
            }
            throw error
        }
        try permit.validate()
        let binding = try installation.resolve().recordingAccount
        if let original = binding?.accountID, original != accountID {
            try invalidate()
            throw RecordingAccountError.differentAccount
        }
        if binding?.accountID == nil {
            try installation.setRecordingAccount(.invalidated(accountID))
        }
        if case .verified = session {} else { session = .identified(accountID, permit) }
        return permit
    }

    /// Identity alone cannot authorize cached history; the authority read must also succeed.
    func acceptAuthority(using permit: DataAccessPermit) throws {
        try permit.validate()
        guard session.permit === permit else { throw RecordingAccountError.verificationRequired }
        let accountID: RecordingAccountID
        switch session {
            case .unverified: throw RecordingAccountError.verificationRequired
            case let .identified(identity, _), let .verified(identity, _): accountID = identity
        }
        if try installation.resolve().recordingAccount != .verified(accountID) {
            try installation.setRecordingAccount(.verified(accountID))
        }
        session = .verified(accountID, permit)
    }

    func rejectAuthority(using permit: DataAccessPermit) throws {
        guard session.permit === permit else { return }
        try invalidate()
    }

    func cachedSession() throws -> DataAccessPermit {
        guard case let .verified(accountID, permit) = session,
              try installation.resolve().recordingAccount == .verified(accountID)
        else { throw RecordingAccountError.verificationRequired }
        try permit.validate()
        return permit
    }
}
