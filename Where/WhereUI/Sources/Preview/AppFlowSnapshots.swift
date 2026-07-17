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
        /// The raised settle floor outlasts the iOS 26 glass toolbar/tab bar
        /// material adaptation, which starts quiet a few hundred ms after
        /// hosting and otherwise intermittently captures pre-adaptation.
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "LoggedIn",
                configurations: .phoneLightDark,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                let model = PreviewSupport.loadedModel()
                RootView(
                    model: model,
                    launcher: WhereLaunch.makeLauncher(model: model, reason: .userForeground),
                )
            }
        }
    }
#endif
