import AppIntents
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
    private let buildEnvironment: WhereBuildEnvironment
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

        private let inspectorModeController: InspectorModeController?

        init(
            buildEnvironment: WhereBuildEnvironment,
            inspectorModeController: InspectorModeController? = nil,
        ) {
            self.buildEnvironment = buildEnvironment
            self.inspectorModeController = inspectorModeController
            intentServices = IntentServices(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: buildEnvironment.storage(
                    forCloudKitValidationBuild: Self.isCloudKitValidationBuild,
                ),
            )
        }

    #else
        init(buildEnvironment: WhereBuildEnvironment) {
            self.buildEnvironment = buildEnvironment
            intentServices = IntentServices(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = Self.makeModel(
                buildEnvironment: buildEnvironment,
                storeStorage: buildEnvironment.storage,
            )
        }
    #endif

    private static func makeModel(
        buildEnvironment: WhereBuildEnvironment,
        storeStorage: SwiftDataStore.Storage,
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
                    widgetRefresher: buildEnvironment.makeWidgetRefresher(),
                    locationOutbox: locationOutbox,
                )
            },
            logSystem: .shared,
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
        let launcher = WhereLaunch
            .makeLauncher(model: model, reason: .undetermined) { [intentServices] in
                await intentServices.install(.forIntents(sharingStoreOf: $0))
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
                inspectorModeController: inspectorModeController,
            ))
        #else
            AnyView(RootView(
                model: model,
                launcher: launcher,
                primaryAppIconName: buildEnvironment.primaryAppIconName,
            ))
        #endif
    }
}
