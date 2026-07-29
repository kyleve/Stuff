import LifecycleKit
import LifecycleKitUI
import PeriscopeUI
import SnapshotKit
import SwiftUI
import WhereCore
#if DEBUG
    import PeriscopeCore
    import PeriscopeTools
#endif

/// The app's root: the launch plan gated in front of `MainTabs`, the Liquid
/// Glass tab bar over three tabs (Locations, Your Year, Settings).
///
/// `LifecycleContainer` renders the splash / onboarding UI while the
/// `LifecycleRunner` runs, then the `TabView` (the real "logged-in" UI — the
/// launch *destination*, not a step) once it reaches `.ready`, built from the
/// session the launch's trunk produced. The model is built at launch (so
/// CoreLocation is wired for background relaunch) and shared down through the
/// environment.
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
        /// The footprint the non-modal floating developer HUD occupies, reported up
        /// from the sibling `DeveloperOverlay` and applied as extra safe area to the
        /// app content so screens behind the HUD can scroll clear of it.
        @State private var developerOverlayInsets = EdgeInsets()
        /// Periscope's "log view mode" mirror, built once the launch bootstrap has
        /// opened the log store. Injected into the environment so
        /// `debugLogInspectable(_:)` badges across the app can reveal their scopes;
        /// the developer overlay binds its toggle to it.
        @State private var inspector: PeriscopeInspector?
        /// Watches the shared pipeline for `.warning`+ records and shows them as
        /// in-app toasts while developing. Retained for the process; started once
        /// the store is available.
        @State private var alerter: PeriscopeAlerter?
        @State private var toastCenter = DeveloperToastCenter()
    #endif
    private let launcher: LifecycleRunner<WhereSession>

    /// Inject the app-owned model + runner built at launch. The app uses this.
    public init(model: WhereModel, launcher: LifecycleRunner<WhereSession>) {
        _model = State(initialValue: model)
        self.launcher = launcher
    }

    /// Convenience for previews and the hosted UI test: build a model and a
    /// foreground runner for it. The runner isn't run by the app delegate
    /// here, so `.task` drives it (see `body`).
    public init() {
        // Mirrors the app root's wiring (see `AppDelegate`). Nothing here
        // attaches a sink unless a scope is actually resolved, which a preview
        // or the hosted UI test never gets to.
        let model = WhereModel(
            preferences: WherePreferences(store: UserDefaults.standard),
            makeBootstrap: { WhereBootstrap() },
            logSystem: .shared,
        )
        _model = State(initialValue: model)
        launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
    }

    public var body: some View {
        ZStack {
            LifecycleContainer(
                launcher,
                transition: revealTransition,
                animation: revealAnimation,
                minimumSplashDuration: stylesheet.launch.minimumSplashDuration,
                splash: { _ in LaunchSplashView() },
                failure: { LifecycleFailureView(failure: $0) },
                gates: {
                    // The gate roots the trunk, so there is no session (and no
                    // open store) behind it yet — onboarding builds the scope
                    // it commits regions with, through the model.
                    GateView(for: OnboardingGate.self) { handle, _ in
                        OnboardingView(gate: handle)
                    }
                },
            ) { session in
                // `.ready` carries the session the launch produced — the app
                // surface cannot render without it. `MainTabs` owns the
                // scene-scoped `YearReportModel` and gets a fresh one whenever
                // a reset rebuilds the session. Keyed on the session's
                // monotonic `id` (never reused within the process) rather than
                // its address, so a rebuilt session can't collide with a freed
                // one and skip the rebuild.
                MainTabs(
                    session: session,
                    initialReport: model.initialReport,
                    selectedYear: model.initialSelectedYear,
                )
                .id(session.id)
            }
            // Extend the app content's safe area by the floating HUD's footprint so
            // scroll views behind the non-modal window inset and their last rows
            // clear it. Scoped to the content only — never the sibling overlay/toast
            // layers below — so the overlay's own geometry can't feed back on itself.
            #if DEBUG
            .safeAreaPadding(developerOverlayInsets)
            #endif

            // The floating developer surface sits above every launch phase and
            // tab so its tools are reachable from anywhere (even logged out). It's
            // DEBUG-only and compiled out of release entirely.
            #if DEBUG
                DeveloperOverlay(tabBarInset: developerTabBarInset)
                // High-severity log toasts float above everything, including the
                // developer overlay, so a warning/error is visible wherever it fires.
                DeveloperToastOverlay(center: toastCenter)
            #endif
        }
        #if DEBUG
        .onPreferenceChange(DeveloperTabBarInsetKey.self) { developerTabBarInset = $0 }
            .onPreferenceChange(DeveloperOverlayInsetKey.self) { developerOverlayInsets = $0 }
            .environment(\.periscopeInspector, inspector)
            .task { configureDeveloperLogging() }
            .onChange(of: model.logStore.map(ObjectIdentifier.init)) { _, _ in
                configureDeveloperLogging()
            }
        #endif
            // Seed the app's root logging context so any view that logs freeform via
            // `\.logContext` emits under the "Where" scope rather than a bare root.
            .logContext(WhereLog.root)
            .environment(model)
            // The logged-in session appears once the launch's `start-session`
            // step builds it. Injected as an optional `Observable`, so the
            // `TabView`'s `@Environment(WhereSession.self)` views resolve it
            // (they only render at `.ready`, by which point it's present) and
            // re-inject when a reset rebuilds it. The DEBUG developer overlay
            // reads it optionally — it can appear before login, where the
            // SwiftData inspector row simply hides.
            .environment(model.session)
            // Which world the app is in, seeded once here so no view has to
            // ask the model. Reading the model's mode tracks its scope state,
            // so entering or leaving demo mode re-renders what branches on it.
            .demoMode(of: model)
            // Settings' "Erase all data & reset" runs the teardown through the
            // `LifecycleProxy` that `LifecycleContainer` publishes into the
            // environment, which wipes data + preferences and re-drives the
            // launch plan back to onboarding.
            //
            // `run()` is idempotent: in the app the delegate already kicked it off,
            // so this is a no-op there; in previews/tests it's what drives the
            // launch.
            //
            // Promote the launch (`.undetermined` from the app delegate, or a
            // genuine `.background` relaunch) only once the scene is genuinely
            // active. SwiftUI may build this view (and run `.task`) for a scene that
            // iOS connected in the background; promoting then would flip the launcher
            // to foreground and build the heavy `TabView` for a launch nobody sees,
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
            // system traits and the app's themes, plus the session's live region
            // styles (`\.regionStyles`) so cards/calendar/onboarding render the
            // user's picked looks. `.default` before the session exists (splash) and
            // reactive after, since reading `session.regionStyles` tracks it.
            .whereBroadwayRoot(regionStyles: model.session?.regionStyles ?? .default)
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

    #if DEBUG
        /// Build the log-view-mode inspector and start the toast alerter once the
        /// launch bootstrap has opened the process-global store. Idempotent: it's
        /// driven from both the initial `.task` (fixtures that inject a store up
        /// front) and an `.onChange` (the app, where the store opens off the
        /// launch path), and does nothing until the store exists or after it's
        /// wired once.
        private func configureDeveloperLogging() {
            guard inspector == nil, let store = model.logStore else { return }
            inspector = PeriscopeInspector(system: .shared, store: store)
            let alerter = PeriscopeAlerter(
                system: .shared,
                threshold: .warning,
                handler: DeveloperToastAlertHandler(center: toastCenter),
            )
            alerter.start()
            self.alerter = alerter
        }
    #endif
}

#if DEBUG
    extension RootView: SnapshotProviding {
        /// The logged-in root is multi-phase async work — splash → launch steps →
        /// `.ready` → `MainTabs` activation → glass-material adaptation — and
        /// every phase is pixel-quiet under capture (motion frozen, animations
        /// disabled), so pixel stability alone can bake *any* intermediate phase
        /// on a slow runner (CI captured the splash and the pre-activation tabs).
        ///
        /// The pre-capture hook awaits the launcher's drive — `run()` is
        /// idempotent and awaits the in-flight drive, a deterministic "reached
        /// `.ready`" signal — so the raised settle floor only has to outlast the
        /// post-ready tail: `MainTabs`' `.task` activation (empty-store re-pull +
        /// Resolve badge) and the iOS 26 glass toolbar/tab bar material
        /// adaptation, which starts quiet a few hundred ms after the chrome
        /// hosts. Those have no reachable completion signal (the scene's report
        /// model is private to `MainTabs`; the adaptation has no public
        /// notification), hence the generous floor — see the flakiness ledger in
        /// `Where/TODOs.md`.
        public static var snapshots: [SnapshotCase] {
            let model = PreviewSupport.loadedModel()
            let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
            whereSnapshot(
                name: "LoggedIn",
                configurations: .phoneLightDark,
                settle: .settledAtLeast(minDuration: 1.5),
                onReadyToSnapshot: { await launcher.run() },
            ) {
                RootView(model: model, launcher: launcher)
            }
        }
    }

    // The from-scratch launch preview (splash → onboarding) — the matrix pins
    // only the logged-in root, so this stays as a bespoke preview alongside the
    // cutsheet.
    #Preview {
        RootView()
    }

    #Preview("Logged in") {
        RootView.snapshotPreviews
    }
#endif
