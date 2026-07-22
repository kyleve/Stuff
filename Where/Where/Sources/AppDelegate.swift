import AppIntents
import UIKit
import WhereCore
import WhereIntents
import WhereUI

/// Owns the app's single `WhereModel` and the launch task that boots it,
/// wiring both up at process launch rather than from a SwiftUI view's
/// `.task`.
///
/// This matters for background relaunch: when CoreLocation relaunches the app
/// after termination (a significant location change or visit), there's no UI,
/// so a view's `.task` is not a reliable hook. `didFinishLaunching` always
/// runs, so starting the launch here (whose synchronous wiring installs the
/// `CLLocationManager`) lets CoreLocation deliver the pending event, while
/// the launch task continues background tracking off the main thread — and
/// parks before its foreground-only tail until a scene genuinely activates
/// (`RootView` reports that).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = WhereModel()

    /// The intent layer's services handoff, owned here — the composition root
    /// — and registered with the App Intents dependency container below, so
    /// intents resolve it via `@Dependency` (no singleton of ours). The launch
    /// installs the store-sharing stack into it via `onServicesReady`.
    let intentServices = IntentServices()

    /// The observable launch state, built in `didFinishLaunching` (which also
    /// starts the launch task) and handed to `RootView` via `WhereApp`.
    private(set) var launchState: WhereLaunchState!

    func application(
        _: UIApplication,
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
        // Open the durable Periscope log store and attach it to the shared
        // logging pipeline. Off the launch critical path (it touches disk); the
        // shared OSLog sink covers logging until the store is attached.
        WhereLaunch.bootstrapLogging(model: model)
        // Start the launch: synchronous must-exist-now wiring (the
        // CLLocationManager, so a queued location event isn't lost; the
        // foreground-notification presenter), then the launch task. The task
        // services a possible headless wake above its scene-activation park;
        // `RootView` reports activation once a scene is genuinely active,
        // which resumes the foreground tail.
        // `onServicesReady` fires on every session (re)start — first launch
        // and each reset relaunch: derive the App Intents stack from the
        // launch's services — same store, attribution, and clock; GPS-free —
        // and install it, so the launch's open is the process's *only* store
        // open and an intent can never race it with a second container over
        // the same file. Intents that fire earlier park in
        // `IntentServices.current()` until this lands; the derivation can't
        // fail, so nothing can strand them parked.
        launchState = WhereLaunch.start(model: model) { [intentServices] in
            await intentServices.install(.forIntents(sharingStoreOf: $0))
        }
        // Index the tracked regions into Spotlight (a search for a region
        // name surfaces Where and its day-count query) through the stack
        // installed above, off the launch critical path. The resolver parks
        // until `onServicesReady` installs the stack, so this needs no
        // launch-completion signal; indexing a handful of items is cheap and
        // idempotent.
        Task {
            await RegionSpotlightIndexer.indexRegions(resolving: intentServices)
        }
        return true
    }
}
