import LifecycleKit
import SwiftUI
import WhereCore

/// The app's root: the launch sequence gated in front of a Liquid Glass tab bar
/// over the three top-level screens.
///
/// `LifecycleContainer` renders the splash / onboarding / migration UI while
/// the `LifecycleRunner` runs, then the `TabView` (the real "logged-in" UI —
/// the launch *destination*, not a step) once it reaches `.ready`. The model is
/// built at launch (so CoreLocation is wired for background relaunch) and shared
/// down through the environment.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhereModel
    private let launcher: LifecycleRunner

    /// Inject the app-owned model + runner built at launch. The app uses this.
    public init(model: WhereModel, launcher: LifecycleRunner) {
        _model = State(initialValue: model)
        self.launcher = launcher
    }

    /// Convenience for previews and the hosted UI test: build a model and a
    /// foreground runner for it. The runner isn't run by the app delegate
    /// here, so `.task` drives it (see `body`).
    public init() {
        let model = WhereModel()
        _model = State(initialValue: model)
        launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
    }

    public var body: some View {
        LifecycleContainer(launcher) {
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
        // launch.
        //
        // Promote a background launch only once the scene is genuinely active.
        // SwiftUI may build this view (and run `.task`) for a scene that iOS
        // connected in the background; promoting then would flip the launcher to
        // foreground and build the heavy `TabView` for a launch nobody sees,
        // defeating the headless path. The `.onChange` below handles the later
        // background→foreground transition; this initial check covers a launch
        // that is already active when the view first appears.
        .task {
            await launcher.run()
            if scenePhase == .active {
                await launcher.enterForeground()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await launcher.enterForeground()
                await model.appBecameActive()
            }
        }
    }
}

#if DEBUG
    #Preview {
        RootView()
    }
#endif
