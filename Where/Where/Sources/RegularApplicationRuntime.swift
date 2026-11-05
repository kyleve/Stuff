import AppIntents
import InstallerKit
import LifecycleKit
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
    let intentServices: IntentServices
    private let updates: UpdateModel?
    private let buildEnvironment: WhereBuildEnvironment
    private let widgetPresentationPublisher: WidgetPresentationPublisher
    private(set) var launcher: LifecycleRunner<WhereSession>!

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
            buildEnvironment: WhereBuildEnvironment,
            preferences: WherePreferences,
            effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
            applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
            developerLaunchController: WhereDeveloperLaunchController? = nil,
        ) {
            self.buildEnvironment = buildEnvironment
            updates = Self.makeUpdates(buildEnvironment: buildEnvironment, preferences: preferences)
            self.developerLaunchController = developerLaunchController
            intentServices = IntentServices()
            widgetPresentationPublisher = WidgetPresentationPublisher(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: buildEnvironment.storage(
                    forCloudKitValidationBuild: Self.isCloudKitValidationBuild,
                ),
                dataset: buildEnvironment
                    .dataset(forCloudKitValidationBuild: Self.isCloudKitValidationBuild),
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
                applyRemoteLogging: applyRemoteLogging,
            )
            if let configuration = developerLaunchController?.consumeDemoConfiguration() {
                model.prepareDemoLaunch(configuration: configuration)
            }
        }

    #else
        init(
            buildEnvironment: WhereBuildEnvironment,
            preferences: WherePreferences,
            effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
            applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
        ) {
            self.buildEnvironment = buildEnvironment
            updates = Self.makeUpdates(buildEnvironment: buildEnvironment, preferences: preferences)
            intentServices = IntentServices()
            widgetPresentationPublisher = WidgetPresentationPublisher(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: buildEnvironment.storage,
                dataset: buildEnvironment.dataset(forCloudKitValidationBuild: false),
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
                applyRemoteLogging: applyRemoteLogging,
            )
        }
    #endif

    private static func makeUpdates(
        buildEnvironment: WhereBuildEnvironment,
        preferences: WherePreferences,
    ) -> UpdateModel? {
        guard buildEnvironment.audience == .development, !buildEnvironment.isRunningTests,
              let installed = BuildInfo.current(bundle: .main).distribution else { return nil }
        let client = UpdateClient(session: URLSession(configuration: .ephemeral))
        return UpdateModel(service: UpdateService(
            installed: installed,
            preferences: preferences,
            client: client,
            now: Date.init,
        ))
    }

    private static func makeModel(
        buildEnvironment: WhereBuildEnvironment,
        storeStorage: SwiftDataStore.Storage,
        dataset: DataCompatibilityDataset,
        preferences: WherePreferences,
        effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
        applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
    ) -> WhereModel {
        let installationContextStore = FileInstallationRecordingContextStore()
        let locationOutbox = FileLocationOutbox.applicationSupport()
        let bootstrap = WhereBootstrap(
            installationContextStore: installationContextStore,
            storeStorage: storeStorage,
            dataset: dataset,
            widgetRefresher: buildEnvironment.makeWidgetRefresher(),
            locationOutbox: locationOutbox,
        )
        return WhereModel(
            preferences: preferences,
            installationContextStore: installationContextStore,
            makeBootstrap: { _ in bootstrap },
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

        WhereLaunch.startAmbientLogging(on: .shared)
        model.onLoggedOut = { [intentServices] in await intentServices.clear() }
        model.onDataCompatibilityBlocked = { [intentServices] error in
            await intentServices.block(error: error)
        }
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
        Task { [launcher, model, intentServices] in
            await launcher.run()
            guard !model.isInDemoMode else { return }
            await RegionSpotlightIndexer.indexRegions(resolving: intentServices)
        }
        return true
    }

    func makeRootView() -> AnyView {
        #if DEBUG
            AnyView(RootView(
                model: model,
                launcher: launcher,
                primaryAppIconName: buildEnvironment.primaryAppIconName,
                updates: updates,
                developerLaunchController: developerLaunchController,
            ))
        #else
            AnyView(RootView(
                model: model,
                launcher: launcher,
                primaryAppIconName: buildEnvironment.primaryAppIconName,
                updates: updates,
            ))
        #endif
    }

    func refreshDataCompatibility() async {
        await model.refreshDataCompatibilityIfNeeded()
    }
}
