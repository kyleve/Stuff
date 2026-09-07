import AppIntents
import LifecycleKit
import os
import PeriscopeCore
import SwiftUI
import UIKit
import WhereCore
import WhereIntents
import WhereUI
#if DEBUG
    import Inspector
#endif

/// The regular Where process: the single model, intent handoff, and lifecycle
/// runner that make up the shipping application.
@MainActor
final class RegularApplicationRuntime: WhereApplicationRuntime {
    let model: WhereModel

    let intentServices = IntentServices()
    private let widgetPresentationPublisher = WidgetPresentationPublisher()
    private(set) var launcher: LifecycleRunner<WhereSession>!
    private let automaticBackupScheduler: AutomaticBackupBackgroundScheduler
    private let backupRecoveryKeys: BackupRecoveryKeyProvider
    private let firstUnlockAvailability: FirstUnlockAvailability
    private var launchBackupClaimedByBackgroundTask = false
    private let logger = Logger(subsystem: "com.stuff.where", category: "AutomaticBackup")

    #if DEBUG
        /// Compiled into Debug device builds created by `Where/install --cloudkit`, so every
        /// foreground, background, and CloudKit-push relaunch uses the same store mode.
        static let isCloudKitValidationBuild: Bool = {
            #if WHERE_CLOUDKIT_VALIDATION
                true
            #else
                false
            #endif
        }()

        private let developerLaunchController: WhereDeveloperLaunchController?

        init(
            preferences: WherePreferences,
            effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
            applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
            developerLaunchController: WhereDeveloperLaunchController? = nil,
        ) {
            let automaticBackupScheduler = AutomaticBackupBackgroundScheduler()
            let firstUnlockAvailability = FirstUnlockAvailability.applicationSupport()
            self.firstUnlockAvailability = firstUnlockAvailability
            let backupRecoveryKeys = BackupRecoveryKeyProvider.system {
                await firstUnlockAvailability.isAvailable()
            }
            self.automaticBackupScheduler = automaticBackupScheduler
            self.backupRecoveryKeys = backupRecoveryKeys
            self.developerLaunchController = developerLaunchController
            model = Self.makeModel(
                storeStorage: Self.storeStorage(
                    forCloudKitValidationBuild: Self.isCloudKitValidationBuild,
                ),
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
                applyRemoteLogging: applyRemoteLogging,
                automaticBackupScheduler: automaticBackupScheduler,
                backupRecoveryKeys: backupRecoveryKeys,
            )
            if let configuration = developerLaunchController?.consumeDemoConfiguration() {
                model.prepareDemoLaunch(configuration: configuration)
            }
        }

        static func storeStorage(
            forCloudKitValidationBuild validatesCloudKit: Bool,
        ) -> SwiftDataStore.Storage {
            validatesCloudKit ? .cloudKit : .localOnly
        }
    #else
        init(
            preferences: WherePreferences,
            effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
            applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
        ) {
            let automaticBackupScheduler = AutomaticBackupBackgroundScheduler()
            let firstUnlockAvailability = FirstUnlockAvailability.applicationSupport()
            self.firstUnlockAvailability = firstUnlockAvailability
            let backupRecoveryKeys = BackupRecoveryKeyProvider.system {
                await firstUnlockAvailability.isAvailable()
            }
            self.automaticBackupScheduler = automaticBackupScheduler
            self.backupRecoveryKeys = backupRecoveryKeys
            model = Self.makeModel(
                storeStorage: .cloudKit,
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
                applyRemoteLogging: applyRemoteLogging,
                automaticBackupScheduler: automaticBackupScheduler,
                backupRecoveryKeys: backupRecoveryKeys,
            )
        }
    #endif

    private static func makeModel(
        storeStorage: SwiftDataStore.Storage,
        preferences: WherePreferences,
        effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
        applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
        automaticBackupScheduler: AutomaticBackupBackgroundScheduler,
        backupRecoveryKeys: BackupRecoveryKeyProvider,
    ) -> WhereModel {
        let installationContextStore = FileInstallationRecordingContextStore()
        let locationOutbox = FileLocationOutbox.applicationSupport()
        return WhereModel(
            preferences: preferences,
            installationContextStore: installationContextStore,
            makeBootstrap: {
                WhereBootstrap(
                    installationContextStore: $0,
                    storeStorage: storeStorage,
                    locationOutbox: locationOutbox,
                    backupRecoveryKeys: backupRecoveryKeys,
                    automaticBackupStorage: AutomaticBackupStorage(),
                    automaticBackupScheduler: automaticBackupScheduler,
                )
            },
            logSystem: .shared,
            effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
            applyRemoteLogging: applyRemoteLogging,
        )
    }

    func didFinishLaunching(
        application _: UIApplication,
        options _: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        AppDependencyManager.shared
            .add(dependency: { [intentServices = self.intentServices] in intentServices })
        automaticBackupScheduler.register { [weak self] in
            await self?.performBackgroundBackup() ?? false
        }
        Task { [weak self] in await self?.initializeRecoveryKey() }

        WhereLaunch.startAmbientLogging(on: .shared)
        model.onLoggedOut = { [intentServices] in await intentServices.clear() }
        model.onThemeChanged = { [intentServices, widgetPresentationPublisher] theme in
            await widgetPresentationPublisher.publish(theme)
            guard !Task.isCancelled else { return }
            await intentServices.updateTheme(theme)
        }
        model.synchronizeTheme()
        let launcher = WhereLaunch
            .makeLauncher(model: model, reason: .undetermined) { [intentServices, model] in
                await intentServices.install(
                    .forIntents(sharingStoreOf: $0),
                    theme: model.theme,
                )
            }
        self.launcher = launcher
        Task { [weak self] in
            guard await self?.firstUnlockAvailability.isAvailable() == true else {
                return
            }
            await self?.driveLaunch()
        }
        return true
    }

    func protectedDataDidBecomeAvailable() {
        Task { [weak self] in
            await self?.initializeRecoveryKey()
            await self?.driveLaunch()
            if self?.launchBackupClaimedByBackgroundTask == true {
                await self?.model.session?.runAutomaticBackupIfDue()
            }
        }
    }

    private func driveLaunch() async {
        await launcher.run()
        guard !model.isInDemoMode else { return }
        // The launcher owns recording, not backup execution. Keep the export
        // out of its unstructured trunk so expiration can cancel the real job.
        if !launchBackupClaimedByBackgroundTask {
            await model.session?.runAutomaticBackupIfDue()
        }
        await RegionSpotlightIndexer.indexRegions(resolving: intentServices)
    }

    private func initializeRecoveryKey() async {
        do {
            _ = try await backupRecoveryKeys.loadOrCreate()
        } catch BackupRecoveryKeyProvider.ProviderError.deferredUntilFirstUnlock {
            // Expected for a background launch before the first unlock.
        } catch {
            logger.error(
                "Recovery-key initialization failed: \(error.localizedDescription, privacy: .public)",
            )
        }
    }

    private func performBackgroundBackup() async -> Bool {
        launchBackupClaimedByBackgroundTask = true
        guard await firstUnlockAvailability.isAvailable() else {
            // Crucially, do not drive the launcher: resolving the scope would
            // open the store before first unlock.
            automaticBackupScheduler.retryAfterFirstUnlock()
            return false
        }

        // didFinishLaunching already drives the shared launch. Do not await
        // its unstructured task or park behind an unanswered onboarding gate.
        do {
            let isReady = try await AutomaticBackupLaunchReadiness.wait {
                switch launcher.phase {
                    case .awaitingGate, .failed: .unavailable
                    case .launching, .running: .pending
                    case .ready: .ready
                }
            }
            guard isReady else {
                await automaticBackupScheduler.reconcile(isEnabled: false, earliestBeginDate: nil)
                return false
            }
            try Task.checkCancellation()
        } catch {
            await model.activeScope?.services.automaticBackups?.cancelCurrentRun()
            if model.session == nil { automaticBackupScheduler.retryAfterFirstUnlock() }
            return false
        }
        guard let result = await model.session?.runAutomaticBackupIfDue() else {
            if model.session == nil { automaticBackupScheduler.retryAfterFirstUnlock() }
            return false
        }
        switch result {
            case .disabled, .notDue, .alreadyRunning, .completed:
                return !Task.isCancelled
            case .deferredUntilFirstUnlock:
                automaticBackupScheduler.retryAfterFirstUnlock()
                return false
        }
    }

    func makeRootView() -> AnyView {
        #if DEBUG
            AnyView(RootView(
                model: model,
                launcher: launcher,
                developerLaunchController: developerLaunchController,
            ))
        #else
            AnyView(RootView(model: model, launcher: launcher))
        #endif
    }
}
