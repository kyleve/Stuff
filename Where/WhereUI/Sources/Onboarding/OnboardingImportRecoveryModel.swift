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
        installationContextStore.backupImportRecovery != nil || installationContextStore
            .photoHistoryReceipt?.acknowledged == false
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
        if let token = installationContextStore.photoHistoryReceipt, !token.acknowledged {
            _ = try await recoverPhoto(token, in: scope, completeOnboarding: completeOnboarding)
        }
        guard installationContextStore.backupImportRecovery != nil else { return }
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
        interruptedImportError = nil
        guard hasInterruptedImport ||
            (requiresOnboarding && installationContextStore.photoHistoryReceipt != nil)
        else {
            return requiresOnboarding
        }
        do {
            let scope = try await resolveScope()
            if let token = installationContextStore.photoHistoryReceipt {
                let completed = try await recoverPhoto(
                    token,
                    in: scope,
                    completeOnboarding: completeOnboarding,
                )
                if installationContextStore.backupImportRecovery == nil {
                    if !completed {
                        await endSession()
                    }
                    return !completed && requiresOnboarding
                }
            }
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
        } catch is DataCompatibilityFailure {
            return false
        } catch is CancellationError {
            return false
        } catch {
            interruptedImportError = error
            return false
        }
    }

    private func recoverPhoto(
        _ token: PhotoHistoryReceipt,
        in scope: WhereScope,
        completeOnboarding: () -> Void,
    ) async throws -> Bool {
        try scope.compatibilityEvents.requireAccess()
        guard scope.compatibilityEvents.domain == token.domain,
              try await scope.services.hasCommittedPhotoHistory(token)
        else {
            try installationContextStore.setPhotoHistoryReceipt(nil)
            return false
        }
        await scope.services.reconcilePhotoHistory()
        try Task.checkCancellation()
        try scope.compatibilityEvents.requireAccess()
        guard try await scope.services.hasCommittedPhotoHistory(token) else {
            try installationContextStore.setPhotoHistoryReceipt(nil)
            return false
        }
        try Task.checkCancellation()
        try scope.compatibilityEvents.requireAccess()
        var terminal = token
        terminal.acknowledged = true
        try installationContextStore.setPhotoHistoryReceipt(terminal)
        completeOnboarding()
        return true
    }

    func takeInterruptedImportError() -> (any Error)? {
        defer { interruptedImportError = nil }
        return interruptedImportError
    }
}
