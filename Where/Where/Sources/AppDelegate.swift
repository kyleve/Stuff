import LifecycleKit
import LogKit
import UIKit
import WhereCore
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

    private let logger = WhereLog.channel(.appDelegate)

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        // A CoreLocation key means iOS woke us headless to service a location
        // event; the runner then skips foreground-only steps (onboarding) and
        // the UI builds no view tree.
        let reason: LifecycleReason = launchOptions?[.location] != nil
            ? .background(.location)
            : .userForeground
        if reason.isBackground {
            logger.info("Relaunched by CoreLocation for a background location event")
        }

        // `initializePrerequisites` installs the CLLocationManager synchronously
        // (so a queued location event isn't lost) and registers the
        // foreground-notification presenter; the rest (store open, etc.) runs as
        // async steps off this synchronous launch path.
        launcher = WhereLaunch.makeLauncher(model: model, reason: reason)
        Task { await launcher.run() }
        return true
    }
}
