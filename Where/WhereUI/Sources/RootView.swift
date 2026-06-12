import LifecycleKit
import SwiftUI
import WhereCore

/// The app's root: the launch sequence gated in front of a Liquid Glass tab bar
/// over the three top-level screens.
///
/// `LaunchContainer` renders the splash / onboarding / migration UI while the
/// `Launcher` runs, then the `TabView` (the real "logged-in" UI — the launch
/// *destination*, not a step) once it reaches `.ready`. The model is built at
/// launch (so CoreLocation is wired for background relaunch) and shared down
/// through the environment.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhereModel
    private let launcher: Launcher

    /// Inject the app-owned model + launcher built at launch. The app uses this.
    public init(model: WhereModel, launcher: Launcher) {
        _model = State(initialValue: model)
        self.launcher = launcher
    }

    /// Convenience for previews and the hosted UI test: build a model and a
    /// foreground launcher for it. The launcher isn't run by the app delegate
    /// here, so `.task` drives it (see `body`).
    public init() {
        let model = WhereModel()
        _model = State(initialValue: model)
        launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
    }

    public var body: some View {
        LaunchContainer(launcher) {
            TabView {
                Tab(Strings.tabPrimary, systemImage: "star.fill") {
                    PrimaryView()
                }

                Tab(Strings.tabElsewhere, systemImage: "globe.americas.fill") {
                    SecondaryView()
                }

                Tab(Strings.tabSettings, systemImage: "gearshape.fill") {
                    SettingsView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        }
        .environment(model)
        // Settings' "Erase all data & reset" runs the teardown through the
        // launcher, which wipes data + preferences and re-drives the launch
        // sequence back to onboarding.
        .environment(\.resetData, ResetDataAction {
            Task { await launcher.reset(WhereLaunch.resetSequence(for: model)) }
        })
        // `run()` is idempotent: in the app the delegate already kicked it off,
        // so this is a no-op there; in previews/tests it's what drives the
        // launch. `enterForeground()` then promotes a background launch now that
        // a window exists (a no-op for a foreground launch).
        .task {
            await launcher.run()
            await launcher.enterForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.appBecameActive() }
        }
    }
}

#if DEBUG
    #Preview {
        RootView()
    }
#endif
