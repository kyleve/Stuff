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
    enum PreflightOutcome: Equatable {
        case noPendingImport
        case rolledBack
        case committed
    }

    enum GateOutcome: Equatable {
        case needsOnboarding
        case recovered
        case failed
    }

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
    ) async throws -> PreflightOutcome {
        guard hasInterruptedImport else { return .noPendingImport }
        switch try await scope.services.backup.importRecoveryState() {
            case .ready:
                return .rolledBack
            case .cleanupRequired:
                completeOnboarding()
                try await scope.services.backup.acknowledgeOnboardingImport()
                try await scope.services.backup.retryImportCleanup()
                return .committed
            case .onboardingAcknowledgementRequired:
                completeOnboarding()
                try await scope.services.backup.acknowledgeOnboardingImport()
                return .committed
        }
    }

    func recoverInterruptedImport(
        requiresOnboarding: Bool,
        resolveScope: () async throws -> WhereScope,
        endSession: () async -> Void,
        completeOnboarding: () -> Void,
    ) async -> GateOutcome {
        guard hasInterruptedImport else {
            return requiresOnboarding ? .needsOnboarding : .recovered
        }
        do {
            let scope = try await resolveScope()
            switch try await scope.services.backup.importRecoveryState() {
                case .ready:
                    await endSession()
                    return .needsOnboarding
                case .cleanupRequired:
                    completeOnboarding()
                    try await scope.services.backup.acknowledgeOnboardingImport()
                    try await scope.services.backup.retryImportCleanup()
                    return .recovered
                case .onboardingAcknowledgementRequired:
                    completeOnboarding()
                    try await scope.services.backup.acknowledgeOnboardingImport()
                    return .recovered
            }
        } catch {
            interruptedImportError = error
            return .failed
        }
    }

    func takeInterruptedImportError() -> (any Error)? {
        defer { interruptedImportError = nil }
        return interruptedImportError
    }
}
