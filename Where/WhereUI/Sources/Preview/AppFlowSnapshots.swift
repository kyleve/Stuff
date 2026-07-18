#if DEBUG
    import LifecycleKit
    import SnapshotKit
    import SwiftUI

    // Snapshot matrices for the app-flow surfaces: the launch splash, onboarding,
    // and the root scene. RootView drives its own launch runner over a preloaded
    // model, so with animations disabled the capture settles on the logged-in UI.

    extension LaunchSplashView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                LaunchSplashView(previewImageName: "AppIconClassic")
            }
            whereSnapshot(name: "SlowLaunchCaption", configurations: .phoneLightDark) {
                LaunchSplashView(previewImageName: "AppIconClassic", previewShowsCaption: true)
            }
        }
    }

    extension OnboardingView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                let model = WhereModel(services: PreviewSupport.previewServices())
                OnboardingView(bridge: LifecycleStepUIBridge(reason: .userForeground))
                    .environment(model)
                    .environment(model.session)
            }
        }
    }

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
#endif
