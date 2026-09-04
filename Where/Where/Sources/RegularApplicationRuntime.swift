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
    private(set) var launcher: LifecycleRunner<WhereSession>!
    private let automaticBackupScheduler: AutomaticBackupBackgroundScheduler
    private let backupRecoveryKeys: BackupRecoveryKeyProvider
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

        private let inspectorModeController: InspectorModeController?

        init(inspectorModeController: InspectorModeController? = nil) {
            let automaticBackupScheduler = AutomaticBackupBackgroundScheduler()
            let backupRecoveryKeys = BackupRecoveryKeyProvider.system {
                await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
            }
            self.automaticBackupScheduler = automaticBackupScheduler
            self.backupRecoveryKeys = backupRecoveryKeys
            self.inspectorModeController = inspectorModeController
            model = Self.makeModel(
                storeStorage: Self.storeStorage(
                    forCloudKitValidationBuild: Self.isCloudKitValidationBuild,
                ),
                automaticBackupScheduler: automaticBackupScheduler,
                backupRecoveryKeys: backupRecoveryKeys,
            )
        }

        static func storeStorage(
            forCloudKitValidationBuild validatesCloudKit: Bool,
        ) -> SwiftDataStore.Storage {
            validatesCloudKit ? .cloudKit : .localOnly
        }
    #else
        init() {
            let automaticBackupScheduler = AutomaticBackupBackgroundScheduler()
            let backupRecoveryKeys = BackupRecoveryKeyProvider.system {
                await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
            }
            self.automaticBackupScheduler = automaticBackupScheduler
            self.backupRecoveryKeys = backupRecoveryKeys
            model = Self.makeModel(
                storeStorage: .cloudKit,
                automaticBackupScheduler: automaticBackupScheduler,
                backupRecoveryKeys: backupRecoveryKeys,
            )
        }
    #endif

    private static func makeModel(
        storeStorage: SwiftDataStore.Storage,
        automaticBackupScheduler: AutomaticBackupBackgroundScheduler,
        backupRecoveryKeys: BackupRecoveryKeyProvider,
    ) -> WhereModel {
        let installationContextStore = FileInstallationRecordingContextStore()
        let locationOutbox = FileLocationOutbox.applicationSupport()
        return WhereModel(
            preferences: WherePreferences(store: UserDefaults.standard),
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
        )
    }

    func didFinishLaunching(
        application: UIApplication,
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
        let launcher = WhereLaunch
            .makeLauncher(model: model, reason: .undetermined) { [intentServices] in
                await intentServices.install(.forIntents(sharingStoreOf: $0))
            }
        self.launcher = launcher
        Task { [weak self] in
            guard application.isProtectedDataAvailable else {
                self?.automaticBackupScheduler.retryAfterFirstUnlock()
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
        }
    }

    private func driveLaunch() async {
        await launcher.run()
        guard !model.isInDemoMode else { return }
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
        guard UIApplication.shared.isProtectedDataAvailable else {
            // Crucially, do not drive the launcher: resolving the scope would
            // open the store before first unlock.
            automaticBackupScheduler.retryAfterFirstUnlock()
            return false
        }

        await launcher.run()
        guard let result = await model.session?.runAutomaticBackupIfDue() else {
            automaticBackupScheduler.retryAfterFirstUnlock()
            return false
        }
        switch result {
            case .disabled, .notDue, .alreadyRunning, .completed:
                return true
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
                inspectorModeController: inspectorModeController,
            ))
        #else
            AnyView(RootView(model: model, launcher: launcher))
        #endif
    }
}
