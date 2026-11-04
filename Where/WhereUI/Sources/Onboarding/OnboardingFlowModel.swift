import Foundation
import LifecycleKit
import Observation
import PeriscopeCore
@_spi(Testing) import WhereCore

/// View-scoped onboarding state and orchestration over WhereCore's backup and recording services.
@MainActor
@Observable
final class OnboardingFlowModel {
    enum Phase: Hashable {
        case intro
        case theme
        case pickRegions
        case customize
        case location
    }

    let installationContext: InstallationRecordingContext
    let gate: LifecycleGateHandle
    var phase: Phase
    var page = 0
    var theme: WhereTheme
    var selection = PrimaryRegionSelectionModel()
    var recordingEnabled: Bool
    var deviceSetup = OnboardingDeviceSetupModel()
    var reminders: OnboardingReminderSettings
    var isFinishing = false
    var restoreSelection = OnboardingRestoreSelection()
    var intro = OnboardingIntroState()
    var showImporter = false
    var showRestoreStrategyDialog = false

    private static let demoBuildDisplayTime = Duration.seconds(2)
    private static let logger = WhereLog.session(OnboardingViewLog.self)

    init(
        gate: LifecycleGateHandle,
        installationContext: InstallationRecordingContext,
        startsAtRecordingChoice: Bool,
        initialTheme: WhereTheme,
        preferences: WherePreferences,
    ) {
        self.gate = gate
        self.installationContext = installationContext
        phase = startsAtRecordingChoice ? .location : .intro
        theme = initialTheme
        reminders = OnboardingReminderSettings(preferences: preferences)
        recordingEnabled = installationContext.automaticRecordingEnabled
            ?? installationContext.recommendedRecordingEnabled
    }

    var failureTitle: String {
        intro.failure?.flow.title ?? ""
    }

    func advanceIntro(pageCount: Int) {
        if page < pageCount - 1 {
            page += 1
        } else {
            discardPendingRestore()
            phase = .theme
        }
    }

    func selectTheme(_ newTheme: WhereTheme, using model: WhereModel) {
        guard newTheme != theme else { return }
        theme = newTheme
        model.previewTheme(newTheme)
    }

    func continueAfterThemeSelection() {
        phase = restoreSelection.readyImport == nil ? .pickRegions : .location
    }

    func requestFinish(using model: WhereModel) {
        guard !isFinishing, !deviceSetup.isLoading else { return }
        if deviceSetup.deviceToRemove != nil {
            deviceSetup.isConfirmingRemoval = true
        } else {
            Task { await finish(using: model) }
        }
    }

    func finish(using model: WhereModel) async {
        guard !isFinishing else { return }
        let deviceToRemove = deviceSetup.deviceToRemove
        let reminderSettings = reminders
        let readyImport = restoreSelection.readyImport
        if restoreSelection.selectedURL != nil {
            guard readyImport != nil else {
                assertionFailure("An onboarding restore must have an explicit import strategy.")
                discardPendingRestore()
                return
            }
            intro.activity = .restoringBackup
            phase = .intro
        }
        isFinishing = true
        do {
            let context = try model.confirmInitialRecordingChoice(
                isEnabled: recordingEnabled,
            )
            guard context.automaticRecordingEnabled != nil else {
                preconditionFailure("A confirmed installation context must carry its choice.")
            }
            reminderSettings.save(to: model.preferences)
        } catch {
            Self.logger.installationContextWriteFailed(
                error: .restricted(.errorDetails, error),
            )
            gate.fail(error)
            return
        }

        let scope: WhereScope
        do {
            scope = try await model.resolveScope()
            if try await model.preflightPendingImportRecovery(in: scope) == .rolledBack {
                // Consent was renewed before this old prepared marker could be checked. No
                // store receipt means Restore never committed; keep that choice available.
                await model.endSession()
                phase = .intro
                intro.activity = .browsing
                isFinishing = false
                return
            }
        } catch {
            Self.logger.scopeCreationFailed(
                error: .restricted(.errorDetails, error),
            )
            gate.fail(error)
            return
        }

        if let readyImport {
            guard await importBackup(readyImport, into: scope, using: model) else { return }
        }

        do {
            try await configureRecording(in: scope, removing: deviceToRemove)
        } catch {
            Self.logger.recordingConfigurationFailed(
                error: .restricted(.errorDetails, error),
            )
            if let summary = restoreSelection.committedSummary {
                gate.fail(OnboardingCommittedImportSetupError(
                    summary: summary,
                    underlying: error,
                ))
            } else {
                gate.fail(error)
            }
            return
        }
        if selection.hasSelection {
            do {
                try await selection.commit(using: scope)
            } catch {
                Self.logger.regionCommitFailed(
                    error: .restricted(.errorDetails, error),
                )
            }
        }
        if !model.hasOnboarded {
            model.completeOnboarding()
        }
        do {
            try model.completeInstallationSetup()
        } catch {
            Self.logger.installationContextWriteFailed(error: .restricted(.errorDetails, error))
            gate.fail(error)
            return
        }
        gate.complete()
    }

    func enterDemoMode(using model: WhereModel) {
        guard !intro.isBuildingDemo else { return }
        intro.activity = .buildingDemo
        Task {
            do {
                async let scope = model.makeDemoScope()
                async let settle: Void = Task.sleep(for: Self.demoBuildDisplayTime)
                _ = try await settle
                try await model.activateDemo(scope)
                gate.complete()
            } catch is CancellationError {
                intro.activity = .browsing
            } catch {
                intro.activity = .failed(.init(flow: .demo, error: error))
                Self.logger.demoBuildFailed(
                    error: .restricted(.errorDetails, error),
                )
            }
        }
    }

    func handleRestoreSelection(_ result: Result<URL, Error>) {
        switch result {
            case let .success(url):
                restoreSelection.select(
                    url: url,
                    hasScopedAccess: url.startAccessingSecurityScopedResource(),
                )
                showRestoreStrategyDialog = true
            case let .failure(error):
                discardPendingRestore()
                intro.activity = .failed(.init(flow: .restoreBackup, error: error))
        }
    }

    func chooseRestoreStrategy(_ strategy: BackupCoordinator.ImportStrategy) {
        guard restoreSelection.selectedURL != nil else {
            assertionFailure("A restore strategy was chosen without a selected backup.")
            return
        }
        restoreSelection.choose(strategy)
        phase = .theme
    }

    func discardPendingRestore() {
        showRestoreStrategyDialog = false
        restoreSelection.discardUncommittedSelection()
    }

    private func importBackup(
        _ readyImport: OnboardingRestoreSelection.ReadyImport,
        into scope: WhereScope,
        using model: WhereModel,
    ) async -> Bool {
        do {
            let summary = try await scope.services.backup.importBackup(
                from: readyImport.url,
                strategy: readyImport.strategy,
            ) { _ in }
            restoreSelection.markCommitted(summary)
            model.completeOnboarding()
            do {
                try await scope.services.backup.acknowledgeOnboardingImport()
            } catch {
                gate.fail(OnboardingCommittedImportSetupError(
                    summary: summary,
                    underlying: error,
                ))
                return false
            }
            return true
        } catch let error as BackupCoordinator.CommittedImportCleanupError {
            restoreSelection.markCommitted(error.summary)
            model.completeOnboarding()
            do {
                try await scope.services.backup.acknowledgeOnboardingImport()
            } catch let acknowledgementError {
                gate.fail(OnboardingCommittedImportSetupError(
                    summary: error.summary,
                    underlying: acknowledgementError,
                ))
                return false
            }
            Self.logger.backupRestoreCleanupFailed(
                error: .restricted(.errorDetails, error.underlying),
            )
            gate.fail(error)
            return false
        } catch let error as BackupCoordinator.CommittedImportSupersededError {
            restoreSelection.markCommitted(error.summary)
            model.completeOnboarding()
            do {
                try await scope.services.backup.acknowledgeOnboardingImport()
            } catch let acknowledgementError {
                gate.fail(OnboardingCommittedImportSetupError(
                    summary: error.summary,
                    underlying: acknowledgementError,
                ))
                return false
            }
            gate.fail(error)
            return false
        } catch let error as BackupCoordinator.ImportRecoveryResolutionError {
            gate.fail(error)
            return false
        } catch {
            restoreSelection.discardUncommittedSelection()
            await model.endSession()
            intro.activity = .failed(.init(flow: .restoreBackup, error: error))
            phase = .intro
            isFinishing = false
            Self.logger.backupRestoreFailed(
                error: .restricted(.errorDetails, error),
            )
            return false
        }
    }

    private func configureRecording(
        in scope: WhereScope,
        removing deviceID: RecordingDeviceID?,
    ) async throws {
        let authorization = await scope.services.ingestor.authorizationStatus()
        do {
            try await scope.services.recording.registerForOnboarding(
                desiredEnabled: recordingEnabled,
                authorization: authorization,
            )
        } catch RecordingPersistenceError.currentDeviceRemoved {
            // The controller published .removed and stopped capture. Finish the gate so the
            // normal launch can expose RemovedDeviceView and its explicit rejoin action.
            return
        }
        if let deviceID {
            _ = try await scope.services.recording.remove(deviceID)
        }
        guard recordingEnabled else { return }
        do {
            try await scope.services.ingestor.requestPermission()
        } catch {
            Self.logger.locationPermissionDenied()
        }
    }
}
