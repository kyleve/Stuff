import LifecycleKit
import SwiftUI
import WhereCore

/// The app's root: the launch sequence gated in front of a Liquid Glass tab bar
/// over the four top-level screens (Primary, Elsewhere, Resolve, Settings).
///
/// `LifecycleContainer` renders the splash / onboarding / migration UI while
/// the `LifecycleRunner` runs, then the `TabView` (the real "logged-in" UI —
/// the launch *destination*, not a step) once it reaches `.ready`. The model is
/// built at launch (so CoreLocation is wired for background relaunch) and shared
/// down through the environment.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stylesheet) private var stylesheet
    @State private var model: WhereModel
    #if DEBUG
        /// The logged-in tab bar's measured height, reported up from `MainTabs` and
        /// handed to the sibling `DeveloperOverlay` so its button rests clear of the
        /// tab bar. Zero when logged out (no tab bar in the tree).
        @State private var developerTabBarInset: CGFloat = 0
    #endif
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
        ZStack {
            LifecycleContainer(
                launcher,
                transition: revealTransition,
                animation: revealAnimation,
                // The splash's slow-launch caption reads "Updating your data…"
                // — allow it only once onboarding has completed. Before that
                // (first install, post-reset relaunch) there is no data to
                // update, and a fresh install's very first store creation
                // routinely outlives the caption delay. Read live so the
                // post-reset relaunch (which clears the flag) suppresses it too.
                splash: { LaunchSplashView(showsDataCaption: model.hasOnboarded) },
                failure: { LifecycleFailureView(failure: $0, retry: $1) },
            ) {
                // At `.ready` the session is always present; `MainTabs` owns the
                // scene-scoped `YearReportModel` and gets a fresh one whenever a reset
                // rebuilds the session. Keyed on the session's monotonic `id` (never
                // reused within the process) rather than its address, so a rebuilt
                // session can't collide with a freed one and skip the rebuild.
                if let session = model.session {
                    MainTabs(
                        session: session,
                        initialReport: model.initialReport,
                        selectedYear: model.initialSelectedYear,
                    )
                    .id(session.id)
                }
            }

            // The floating developer surface sits above every launch phase and
            // tab so its tools are reachable from anywhere (even logged out). It's
            // DEBUG-only and compiled out of release entirely.
            #if DEBUG
                DeveloperOverlay(tabBarInset: developerTabBarInset)
            #endif
        }
        #if DEBUG
        .onPreferenceChange(DeveloperTabBarInsetKey.self) { developerTabBarInset = $0 }
        #endif
        .environment(model)
        // The logged-in session appears once `open-store` builds it. Injected
        // as an optional `Observable`, so the `TabView`'s `@Environment(WhereSession.self)`
        // views resolve it (they only render at `.ready`, by which point it's
        // present) and re-inject when a reset rebuilds it. The DEBUG developer
        // overlay reads it optionally — it can appear before login, where the
        // SwiftData inspector row simply hides.
        .environment(model.session)
        // Settings' "Erase all data & reset" runs the teardown through the
        // `LifecycleRunner` that `LifecycleContainer` publishes into the
        // environment, which wipes data + preferences and re-drives the launch
        // sequence back to onboarding.
        //
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
        // that is already active when the view first appears — and it must run
        // *before* awaiting `run()`: when the scene arrives already active,
        // `.onChange` never fires, and promoting only after `run()` returns
        // would leave the user staring at the empty background surface for the
        // entire (possibly slow) headless drive instead of the splash.
        .task {
            if scenePhase == .active {
                await launcher.enterForeground()
            }
            await launcher.run()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await launcher.enterForeground()
                await model.session?.appBecameActive()
            }
        }
        // Seed the Broadway context at the app root so descendants resolve
        // `WhereStylesheet` (via `@Environment(\.stylesheet)`) against the live
        // system traits and the app's themes.
        .whereBroadwayRoot()
    }

    /// How the launch splash gives way to the app once the runner is `.ready`:
    /// the splash scales up and fades while the `TabView` stays put beneath it
    /// (`insertion: .identity`), reading as the icon zooming toward the viewer to
    /// uncover the UI. Reduce Motion swaps this for a plain crossfade.
    private var revealTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .identity,
            removal: .scale(scale: 16).combined(with: .opacity),
        )
    }

    private var revealAnimation: Animation {
        reduceMotion ? stylesheet.motion.reducedReveal : stylesheet.motion.reveal
    }
}

#if DEBUG
    private struct LoggedInRootPreview: View {
        private let model = PreviewSupport.loadedModel()

        var body: some View {
            RootView(
                model: model,
                launcher: WhereLaunch.makeLauncher(model: model, reason: .userForeground),
            )
        }
    }

    #Preview {
        RootView()
    }

    #Preview("Logged in") {
        LoggedInRootPreview()
    }
#endif
