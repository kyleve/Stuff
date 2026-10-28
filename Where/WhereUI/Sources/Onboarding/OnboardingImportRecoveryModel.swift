import Foundation
import WhereCore

/// Reconciles an onboarding backup import that crossed a process boundary.
///
/// The installation sidecar is authoritative until Core proves whether the
/// store transaction committed. This coordinator keeps that recovery protocol
/// out of the process-wide `WhereModel`; the model only supplies its existing
/// scope and onboarding lifecycle intents.
@MainActor
final class OnboardingImportRecoveryModel {
    private let installationContextStore: any InstallationRecordingContextStoring
    private var interruptedImportError: (any Error)?

    init(installationContextStore: any InstallationRecordingContextStoring) {
        self.installationContextStore = installationContextStore
    }

    var hasInterruptedImport: Bool {
        installationContextStore.backupImportRecovery != nil
    }

    func repairCompletedImportIfNeeded(
        hasOnboarded: Bool,
        completeOnboarding: () -> Void,
    ) {
        guard installationContextStore.onboardingImportCompletion != nil,
              !hasOnboarded
        else { return }
        completeOnboarding()
    }

    func preflightPendingImport(
        in scope: WhereScope,
        completeOnboarding: () -> Void,
    ) async throws {
        guard hasInterruptedImport else { return }
        switch try await scope.services.backup.importRecoveryState() {
            case .ready:
                return
            case .cleanupRequired:
                completeOnboarding()
                try await scope.services.backup.acknowledgeOnboardingImport()
                try await scope.services.backup.retryImportCleanup()
            case .onboardingAcknowledgementRequired:
                completeOnboarding()
                try await scope.services.backup.acknowledgeOnboardingImport()
        }
    }

    func recoverInterruptedImport(
        requiresOnboarding: Bool,
        resolveScope: () async throws -> WhereScope,
        endSession: () async -> Void,
        completeOnboarding: () -> Void,
    ) async -> Bool {
        guard hasInterruptedImport else {
            return requiresOnboarding
        }
        do {
            let scope = try await resolveScope()
            switch try await scope.services.backup.importRecoveryState() {
                case .ready:
                    await endSession()
                    return true
                case .cleanupRequired:
                    completeOnboarding()
                    try await scope.services.backup.acknowledgeOnboardingImport()
                    try await scope.services.backup.retryImportCleanup()
                    return false
                case .onboardingAcknowledgementRequired:
                    completeOnboarding()
                    try await scope.services.backup.acknowledgeOnboardingImport()
                    return false
            }
        } catch {
            interruptedImportError = error
            return false
        }
    }

    func takeInterruptedImportError() -> (any Error)? {
        defer { interruptedImportError = nil }
        return interruptedImportError
    }
}
