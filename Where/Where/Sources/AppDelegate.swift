import CoreLocation
import LifecycleKit
import UIKit
import WhereCore
import WhereIntents
import WhereUI

/// Owns the app's single `WhereModel` and the `LifecycleRunner` that drives
/// launch, wiring both up at process launch rather than from a SwiftUI view's
/// `.task`.
///
/// This matters for background relaunch: when CoreLocation relaunches the app
/// after termination (a significant location change or visit), there's no UI,
/// so a view's `.task` is not a reliable hook. `didFinishLaunching` always
/// runs, so building the runner here (whose synchronous
/// `initializePrerequisites` installs the `CLLocationManager`) lets CoreLocation
/// deliver the pending event, while the async launch steps continue background
/// tracking off the main thread.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = WhereModel()

    /// The launch engine, built in `didFinishLaunching` (where the launch
    /// reason is known) and handed to `RootView` via `WhereApp`.
    private(set) var launcher: LifecycleRunner!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        // A `.background` launch state means iOS woke us headless (replacing the
        // deprecated `launchOptions[.location]` check); authorization tells us
        // whether that could have been the location wake we register for.
        let reason = WhereLaunch.lifecycleReason(
            from: application.applicationState,
            locationAuthorization: CLLocationManager().authorizationStatus,
        )
        // `initializePrerequisites` installs the CLLocationManager synchronously
        // (so a queued location event isn't lost) and registers the
        // foreground-notification presenter; the rest (store open, etc.) runs as
        // async steps off this synchronous launch path.
        launcher = WhereLaunch.makeLauncher(model: model, reason: reason)
        Task {
            await launcher.run()
            // Index the tracked regions into Spotlight (a search for a region
            // name surfaces Where and its day-count query) only after the launch
            // drive finishes, so the intents stack resolves the canonical store
            // the `open-store` step opened instead of assembling itself on the
            // launch critical path. Indexing a handful of items is cheap and
            // idempotent.
            await RegionSpotlightIndexer.indexRegions()
        }
        return true
    }
}
