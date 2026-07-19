import AppIntents
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

    /// The intent layer's services handoff, owned here — the composition root
    /// — and registered with the App Intents dependency container below, so
    /// intents resolve it via `@Dependency` (no singleton of ours). The launch
    /// installs the store-sharing stack into it via `onServicesReady`.
    let intentServices = IntentServices()

    /// The launch engine, built in `didFinishLaunching` (where the launch
    /// reason is known) and handed to `RootView` via `WhereApp`.
    private(set) var launcher: LifecycleRunner!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        // Register the handoff before anything async: the system only delivers
        // intents once launching finishes, so `@Dependency` can always resolve.
        // The provider-closure overload (not the autoclosure one) lets the
        // capture list carry the Sendable actor reference explicitly, without
        // touching `self` at resolution time.
        //
        // Note the registration→resolution plumbing is deliberately untested:
        // `@Dependency` fatal-errors outside "the intent perform flow", so no
        // in-process test can resolve it (a probe was tried and trapped) —
        // verifying it means invoking a Siri/Shortcuts intent on a device.
        // In production this runs exactly once per process. The app-hosted
        // WhereTests bundle re-registers (host launch + the delegate-building
        // test) and AppDependencyManager tolerates that, but the behavior is
        // undocumented — don't add tests that build further AppDelegates.
        AppDependencyManager.shared
            .add(dependency: { [intentServices = self.intentServices] in intentServices })
        // A `.background` launch state means iOS woke us headless (replacing the
        // deprecated `launchOptions[.location]` check); authorization tells us
        // whether that could have been the location wake we register for.
        let reason = WhereLaunch.lifecycleReason(
            from: application.applicationState,
            locationAuthorization: CLLocationManager().authorizationStatus,
        )
        // Open the durable Periscope log store and attach it to the shared
        // logging pipeline. Off the launch critical path (it touches disk); the
        // shared OSLog sink covers logging until the store is attached.
        WhereLaunch.bootstrapLogging(model: model)
        // `initializePrerequisites` installs the CLLocationManager synchronously
        // (so a queued location event isn't lost) and registers the
        // foreground-notification presenter; the rest (store open, etc.) runs as
        // async steps off this synchronous launch path.
        // `onServicesReady` fires from the `open-store` step on every session
        // (re)start: derive the App Intents stack from the launch's services —
        // same store, attribution, and clock; GPS-free — and install it, so
        // the launch's open is the process's *only* store open and an intent
        // can never race it with a second container over the same file (two
        // containers racing to create it on a fresh install is how the launch
        // once failed). Intents that fire earlier park in
        // `IntentServices.current()` until this lands; the derivation can't
        // fail, so nothing can strand them parked.
        launcher = WhereLaunch.makeLauncher(model: model, reason: reason) { [intentServices] in
            await intentServices.install(.forIntents(sharingStoreOf: $0))
        }
        Task {
            await launcher.run()
            // Index the tracked regions into Spotlight (a search for a region
            // name surfaces Where and its day-count query) through the stack
            // installed above, off the launch critical path. Indexing a
            // handful of items is cheap and idempotent.
            await RegionSpotlightIndexer.indexRegions(resolving: intentServices)
        }
        return true
    }
}
