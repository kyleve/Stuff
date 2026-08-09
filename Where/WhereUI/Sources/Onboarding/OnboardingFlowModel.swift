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
        case pickRegions
        case customize
        case photos
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
    var selection = PrimaryRegionSelectionModel()
    var photoImport = OnboardingPhotoImportModel()
    var recordingEnabled: Bool
    var deviceDiscovery = DeviceDiscovery.idle
    var isFinishing = false
    var restoreSelection = OnboardingRestoreSelection()
    var intro = OnboardingIntroState()
    var showImporter = false
    var showRestoreStrategyDialog = false

    private var pendingPhotoDraft: PhotoHistoryDraft?

    private static let demoBuildDisplayTime = Duration.seconds(2)
    private static let logger = WhereLog.session(OnboardingViewLog.self)

    init(
        gate: LifecycleGateHandle,
        installationContext: InstallationRecordingContext,
        startsAtRecordingChoice: Bool,
    ) {
        self.gate = gate
        self.installationContext = installationContext
        phase = startsAtRecordingChoice ? .location : .intro
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
            phase = .pickRegions
        }
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

    func scanPhotos(using model: WhereModel) {
        photoImport.beginScan()
        Task {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            await photoImport.scan(
                library: model.photoLibrary,
                year: WhereModel.currentYear,
                regions: selection.selectedRegions,
                calendar: calendar,
                now: Date(),
            )
        }
    }

    func approvePhotoHistory() {
        guard let draft = photoImport.beginImport() else { return }
        pendingPhotoDraft = draft
        phase = .location
    }

    func skipPhotoHistory() {
        pendingPhotoDraft = nil
        phase = .location
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

            if selection.hasSelection {
                do {
                    try await selection.commit(using: scope)
                } catch {
                    Self.logger(attachments: [.error(error, name: "commit-error")]) {
                        .regionCommitFailed(description: error.localizedDescription)
                    }
                    if pendingPhotoDraft != nil {
                        photoImport.importFailed(error)
                        isFinishing = false
                        phase = .photos
                        return
                    }
                }
            }

            if let pendingPhotoDraft {
                guard await importPhotoHistory(pendingPhotoDraft, into: scope) else { return }
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
        phase = .location
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

    private func importPhotoHistory(
        _ draft: PhotoHistoryDraft,
        into scope: WhereScope,
    ) async -> Bool {
        do {
            let sample = await scope.services.ingestor.currentLocation()
            let location = sample.map {
                CapturedLocation(
                    coordinate: $0.coordinate,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    timestamp: $0.timestamp,
                )
            }
            let history = draft.approvedImport(audit: ManualEntryAudit(
                recordedAt: Date(),
                note: nil,
                location: location,
            ))
            try await scope.services.journal.importPhotoHistory(history)
            pendingPhotoDraft = nil
            return true
        } catch is CancellationError {
            photoImport.importCancelled()
        } catch {
            photoImport.importFailed(error)
            Self.logger(attachments: [.error(error, name: "photo-import-error")]) {
                .photoImportFailed(description: error.localizedDescription)
            }
        }
        isFinishing = false
        phase = .photos
        return false
    }
}
