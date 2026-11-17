import AppIntents
import CloudKit
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
    private let configuredStorage: SwiftDataStore.Storage
    private let widgetPresentationPublisher: WidgetPresentationPublisher
    private(set) var launcher: LifecycleRunner<WhereSession>!

    #if DEBUG
        private let developerLaunchController: WhereDeveloperLaunchController?

        init(
            buildEnvironment: WhereBuildEnvironment,
            preferences: WherePreferences,
            effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
            applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
            developerLaunchController: WhereDeveloperLaunchController? = nil,
        ) {
            self.buildEnvironment = buildEnvironment
            configuredStorage = buildEnvironment.storage
            updates = Self.makeUpdates(buildEnvironment: buildEnvironment, preferences: preferences)
            self.developerLaunchController = developerLaunchController
            intentServices = IntentServices(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            widgetPresentationPublisher = WidgetPresentationPublisher(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: configuredStorage,
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
            configuredStorage = buildEnvironment.storage
            updates = Self.makeUpdates(buildEnvironment: buildEnvironment, preferences: preferences)
            intentServices = IntentServices(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            widgetPresentationPublisher = WidgetPresentationPublisher(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: configuredStorage,
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
        preferences: WherePreferences,
        effectiveDiagnosticReportingConfiguration: DiagnosticReportingConfiguration,
        applyRemoteLogging: @escaping DiagnosticReportingSettingsModel.ApplyRemoteLogging,
    ) -> WhereModel {
        let installationContextStore = FileInstallationRecordingContextStore()
        let locationOutbox = FileLocationOutbox.applicationSupport()
        let installationLocation = InstallationLocation.live()
        // Match SwiftData's CloudKit container. Signing entitlements select its
        // Development or Production environment, independently of the app audience.
        let transport: any DataCompatibilityTransport = storeStorage.usesCloudKit
            ? CloudKitDataCompatibilityTransport(
                containerIdentifier: "iCloud.com.stuff.where",
                version: .current,
            )
            : LocalDataCompatibilityTransport(version: .current)
        let receipts: any DataCompatibilityReceiptStoring = buildEnvironment.isRunningTests
            ? InMemoryDataCompatibilityReceiptStore(receipt: nil)
            :
            AppGroupDataCompatibilityReceipt(appGroupIdentifier: buildEnvironment
                .appGroupIdentifier)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .current,
        )
        let compatibility = WhereCompatibilityModel(coordinator: coordinator)
        return WhereModel(
            preferences: preferences,
            installationContextStore: installationContextStore,
            makeBootstrap: {
                WhereBootstrap(
                    installationContextStore: $0,
                    storeStorage: storeStorage,
                    widgetRefresher: buildEnvironment.makeWidgetRefresher(),
                    locationOutbox: locationOutbox,
                    compatibility: coordinator,
                    installationLocation: installationLocation,
                )
            },
            logSystem: .shared,
            compatibility: compatibility,
            installationLocation: installationLocation,
            effectiveDiagnosticReportingConfiguration: effectiveDiagnosticReportingConfiguration,
            applyRemoteLogging: applyRemoteLogging,
        )
    }

    func didFinishLaunching(
        application: UIApplication,
        options _: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        AppDependencyManager.shared
            .add(dependency: { [intentServices = self.intentServices] in intentServices })

        WhereLaunch.startAmbientLogging(on: .shared)
        model.compatibility
            .onBlocked = { [intentServices] failure in await intentServices.block(failure) }
        model.onLoggedOut = { [intentServices, weak compatibility = model.compatibility] in
            if case let .blocked(failure) = compatibility?.coordinator.state {
                await intentServices.block(failure)
            } else { await intentServices.clear() }
        }
        if configuredStorage.usesCloudKit {
            // Register for silent compatibility updates; this does not request
            // authorization to display notifications.
            application.registerForRemoteNotifications()
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

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult
    {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID
            == CloudKitDataCompatibilityTransport.subscriptionID else { return .noData }
        await model.compatibility.refresh(model: model)
        return .newData
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
}
