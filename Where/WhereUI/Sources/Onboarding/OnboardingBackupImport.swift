import Foundation
import WhereCore

/// Keeps one onboarding import alive across compatibility blocks. Core resolves the receipt
/// before this operation can retry the archive write or accept the committed summary.
@MainActor
struct OnboardingBackupImport {
    let backup: BackupCoordinator
    let compatibility: DataCompatibilityModel

    func run(
        from url: URL,
        strategy: BackupCoordinator.ImportStrategy,
        approval: DataCompatibilityActivationApproval,
    ) async throws -> BackupCoordinator.ImportSummary {
        while true {
            let interruptedImport: any Error
            do {
                // A bare compatibility error means preflight failed or rollback was confirmed.
                return try await compatibility.withAccessRetry {
                    try await backup.importBackup(
                        from: url,
                        strategy: strategy,
                        compatibilityApproval: approval,
                    ) { _ in }
                }
            } catch let error as BackupCoordinator.ImportRecoveryResolutionError {
                guard let failure = error.underlying as? DataCompatibilityError else { throw error }
                interruptedImport = error
                try await compatibility.waitForRecovery(from: failure)
            } catch let error as BackupCoordinator.CommittedImportCleanupError {
                guard let failure = error.underlying as? DataCompatibilityError else { throw error }
                interruptedImport = error
                try await compatibility.waitForRecovery(from: failure)
            }

            let outcome = try await compatibility.withAccessRetry {
                try await backup.retryImportCleanup()
            }
            switch outcome {
                case .nothingPending:
                    // Another caller resolved the marker. Without a rollback proof, never replay.
                    throw interruptedImport
                case .rolledBack:
                    continue
                case let .committed(summary):
                    return summary
            }
        }
    }
}
