import Foundation

/// Account identity is scoped to the CloudKit container. Local development has no cloud account.
public enum RecordingAccountID: Codable, Hashable, Sendable {
    case local
    case cloudKit(recordName: String)
}

/// Durable trust for the installation's authority projection. Invalidation retains its owner.
public enum RecordingAccountBinding: Codable, Equatable, Sendable {
    case verified(RecordingAccountID)
    case invalidated(RecordingAccountID?)

    public var accountID: RecordingAccountID? {
        switch self {
            case let .verified(accountID): accountID
            case let .invalidated(accountID): accountID
        }
    }
}

public enum RecordingAccountError: Error, LocalizedError, Equatable, Sendable {
    case verificationRequired
    case differentAccount

    public var errorDescription: String? {
        switch self {
            case .verificationRequired: String(localized: .recordingAccountVerificationRequired)
            case .differentAccount: String(localized: .recordingAccountDifferentAccount)
        }
    }
}
