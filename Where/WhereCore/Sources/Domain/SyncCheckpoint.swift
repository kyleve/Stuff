import Foundation

public struct SyncCheckpoint: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case idle
        case pendingUpload
        case pendingDownload
        case syncing
        case failed
    }

    public let state: State
    public let lastSuccessfulSyncAt: Date?
    public let lastAttemptAt: Date?
    public let failureReason: String?

    public init(
        state: State,
        lastSuccessfulSyncAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        failureReason: String? = nil,
    ) {
        self.state = state
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastAttemptAt = lastAttemptAt
        self.failureReason = failureReason
    }
}
