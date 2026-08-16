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

    enum DeviceDiscovery: Equatable {
        case idle
        case loading
        case ready(RecordingOnboardingRecommendation)
        case failed(String)
    }

    let installationContext: InstallationRecordingContext
    let gate: LifecycleGateHandle
    var phase: Phase
    var page = 0
    var theme: WhereTheme
    var selection = PrimaryRegionSelectionModel()
    var recordingEnabled: Bool
    var deviceDiscovery = DeviceDiscovery.idle
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
    ) {
        self.gate = gate
        self.installationContext = installationContext
        phase = startsAtRecordingChoice ? .location : .intro
        theme = initialTheme
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

    func discoverRecordingDevices(using model: WhereModel) async {
        guard deviceDiscovery == .idle else { return }
        deviceDiscovery = .loading
        do {
            let recommendation = try await model.discoverRecordingRecommendation(
                for: installationContext,
            )
            deviceDiscovery = .ready(recommendation)
            if installationContext.automaticRecordingEnabled == nil {
                recordingEnabled = recommendation.isEnabled
            }
        } catch {
            deviceDiscovery = .failed(error.localizedDescription)
        }
    }

    func finish(using model: WhereModel) {
        guard !isFinishing else { return }
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
        Task {
            do {
                let context = try model.confirmInitialRecordingChoice(
                    isEnabled: recordingEnabled,
                )
                guard context.automaticRecordingEnabled != nil else {
                    preconditionFailure("A confirmed installation context must carry its choice.")
                }
            } catch {
                Self.logger(attachments: [.error(error, name: "context-error")]) {
                    .installationContextWriteFailed(description: error.localizedDescription)
                }
                gate.fail(error)
                return
            }

            let scope: WhereScope
            do {
                scope = try await model.resolveScope()
            } catch {
                Self.logger(attachments: [.error(error, name: "scope-error")]) {
                    .scopeCreationFailed(description: error.localizedDescription)
                }
                gate.fail(error)
                return
            }

            if let readyImport {
                guard await importBackup(readyImport, into: scope, using: model) else { return }
            }

            do {
                try await configureRecording(in: scope)
            } catch {
                Self.logger(attachments: [.error(error, name: "recording-configuration-error")]) {
                    .recordingConfigurationFailed(description: error.localizedDescription)
                }
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
                    Self.logger(attachments: [.error(error, name: "commit-error")]) {
                        .regionCommitFailed(description: error.localizedDescription)
                    }
                }
            }
            if !model.hasOnboarded {
                model.completeOnboarding()
            }
            gate.complete()
        }
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
                Self.logger(attachments: [.error(error, name: "demo-error")]) {
                    .demoBuildFailed(description: error.localizedDescription)
                }
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
            Self.logger(attachments: [.error(error.underlying, name: "cleanup-error")]) {
                .backupRestoreCleanupFailed(description: error.underlying.localizedDescription)
            }
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
            Self.logger(attachments: [.error(error, name: "restore-error")]) {
                .backupRestoreFailed(description: error.localizedDescription)
            }
            return false
        }
    }

    private func configureRecording(in scope: WhereScope) async throws {
        let authorization = await scope.services.ingestor.authorizationStatus()
        try await scope.services.recording.registerForOnboarding(
            desiredEnabled: recordingEnabled,
            authorization: authorization,
        )
        guard recordingEnabled else { return }
        do {
            try await scope.services.ingestor.requestPermission()
        } catch {
            Self.logger { .locationPermissionDenied }
        }
    }
}
