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
            model = WhereModel(
                preferences: WherePreferences(store: UserDefaults.standard),
                makeBootstrap: {
                    WhereBootstrap(
                        storage: buildEnvironment.storage,
                        widgetRefresher: buildEnvironment.makeWidgetRefresher(),
                    )
                },
                logSystem: .shared,
            )
        }
    #else
        init(buildEnvironment: WhereBuildEnvironment) {
            self.buildEnvironment = buildEnvironment
            intentServices = IntentServices(
                appGroupIdentifier: buildEnvironment.appGroupIdentifier,
            )
            model = WhereModel(
                preferences: WherePreferences(store: UserDefaults.standard),
                makeBootstrap: {
                    WhereBootstrap(
                        storage: buildEnvironment.storage,
                        widgetRefresher: buildEnvironment.makeWidgetRefresher(),
                    )
                },
                logSystem: .shared,
            )
        }
    #endif

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
