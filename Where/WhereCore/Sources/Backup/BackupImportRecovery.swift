import Foundation

extension BackupCoordinator {
    /// Immutable identity and result of one import attempt, persisted before the store write.
    public struct ImportRecoveryDetails: Sendable, Hashable {
        public let transactionID: UUID
        public let strategy: ImportStrategy
        public let summary: ImportSummary

        public init(
            transactionID: UUID,
            strategy: ImportStrategy,
            summary: ImportSummary,
        ) {
            self.transactionID = transactionID
            self.strategy = strategy
            self.summary = summary
        }
    }

    /// Durable half of the two-phase import protocol.
    ///
    /// A prepared marker is written before the store transaction. The transaction inserts a
    /// matching receipt atomically with imported rows, allowing a new process to distinguish a
    /// rolled-back attempt from a committed one. Once promoted to committed, this marker remains
    /// authoritative even after the receipt is deleted.
    public enum DurableImportRecovery: Sendable, Hashable {
        case prepared(ImportRecoveryDetails)
        case committed(
            ImportRecoveryDetails,
            cleanupCompleted: Bool,
            onboardingAcknowledged: Bool,
        )

        public var details: ImportRecoveryDetails {
            switch self {
                case let .prepared(details), let .committed(details, _, _): details
            }
        }
    }

    /// Terminal device-local proof that an onboarding import was accepted by the app layer.
    /// It is independent of active recovery so clearing a finished marker or starting a later
    /// Settings import cannot make Restore eligible again.
    public struct OnboardingImportCompletion: Sendable, Hashable {
        public let transactionID: UUID

        public init(transactionID: UUID) {
            self.transactionID = transactionID
        }
    }
}

/// Persistence seam for onboarding import recovery and its terminal completion proof.
public protocol BackupImportRecoveryPersisting: Sendable {
    func loadBackupImportRecovery() async throws -> BackupCoordinator.DurableImportRecovery?
    func saveBackupImportRecovery(
        _ recovery: BackupCoordinator.DurableImportRecovery?,
    ) async throws
    func recordOnboardingImportCompletion(
        _ completion: BackupCoordinator.OnboardingImportCompletion,
    ) async throws
}

/// No-op recovery persistence for worlds that cannot outlive the process, such as demo mode.
public struct NoopBackupImportRecoveryPersistence: BackupImportRecoveryPersisting {
    public init() {}

    public func loadBackupImportRecovery() async throws
        -> BackupCoordinator.DurableImportRecovery?
    {
        nil
    }

    public func saveBackupImportRecovery(
        _: BackupCoordinator.DurableImportRecovery?,
    ) async throws {}

    public func recordOnboardingImportCompletion(
        _: BackupCoordinator.OnboardingImportCompletion,
    ) async throws {}
}

/// Store receipt committed atomically with one backup import.
///
/// The device-local sidecar supplies the token to query, so a receipt synced from another
/// installation cannot create recovery work here. A receipt is stamped with the transaction's
/// epoch, but remains discoverable after that epoch is superseded: the rows may be inert, yet the
/// receipt still proves the physical save happened and prevents an automatic reapply.
public struct BackupImportReceipt: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let installationID: RecordingDeviceID
    public let dataEpochID: WhereDataEpochID
}
