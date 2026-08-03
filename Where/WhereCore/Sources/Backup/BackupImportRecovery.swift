import Foundation

extension BackupCoordinator {
    /// Why an archive is being imported. Onboarding imports retain their durable commit marker
    /// until the backed-up onboarding preference has been written and explicitly acknowledged.
    public enum ImportPurpose: Sendable, Hashable {
        case onboarding
        case settings
    }

    /// Immutable identity and result of one import attempt, persisted before the store write.
    public struct ImportRecoveryDetails: Sendable, Hashable {
        public let transactionID: UUID
        public let strategy: ImportStrategy
        public let summary: ImportSummary
        public let purpose: ImportPurpose

        public init(
            transactionID: UUID,
            strategy: ImportStrategy,
            summary: ImportSummary,
            purpose: ImportPurpose,
        ) {
            self.transactionID = transactionID
            self.strategy = strategy
            self.summary = summary
            self.purpose = purpose
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

    /// Async persistence seam for the device-local, backup-excluded installation sidecar's active
    /// recovery and terminal onboarding proof. Production bridges this to
    /// `InstallationRecordingContextStoring`; tests can share an in-memory implementation across
    /// recreated coordinators.
    public struct ImportRecoveryPersistence: Sendable {
        let load: @Sendable () async throws -> DurableImportRecovery?
        let save: @Sendable (DurableImportRecovery?) async throws -> Void
        let recordOnboardingCompletion: @Sendable (OnboardingImportCompletion) async throws -> Void

        public init(
            load: @escaping @Sendable () async throws -> DurableImportRecovery?,
            save: @escaping @Sendable (DurableImportRecovery?) async throws -> Void,
            recordOnboardingCompletion: @escaping @Sendable (
                OnboardingImportCompletion,
            ) async throws -> Void,
        ) {
            self.load = load
            self.save = save
            self.recordOnboardingCompletion = recordOnboardingCompletion
        }

        public static let none = ImportRecoveryPersistence(
            load: { nil },
            save: { _ in },
            recordOnboardingCompletion: { _ in },
        )
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
