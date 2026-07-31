import AppIntents
import LifecycleKit
import PeriscopeCore
import UIKit
import WhereCore
import WhereIntents
import WhereUI

/// Owns the app's single `WhereModel` and the `LifecycleRunner` that drives
/// launch, wiring both up at process launch rather than from a SwiftUI view's
/// `.task`.
///
/// This matters for background relaunch on a participating iPhone or iPad:
/// when CoreLocation relaunches the app after termination (a significant
/// location change or visit), there's no UI, so a view's `.task` is not a
/// reliable hook. `didFinishLaunching` always runs, so building the runner here
/// (whose synchronous `initializePrerequisites` installs the
/// `CLLocationManager` on those hosts) lets CoreLocation deliver the pending
/// event, while the async launch steps continue background tracking off the
/// main thread. Mac Catalyst skips the location prerequisite entirely.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app's model, logging into the process-wide Periscope system. This is
    /// where that system enters the model graph: every scope the model creates
    /// registers its sink on the system handed down from here, so nothing below
    /// reaches for the global (and a test hands down a private one).
    let model = WhereModel(
        preferences: WherePreferences(store: UserDefaults.standard),
        makeBootstrap: { WhereBootstrap() },
        logSystem: .shared,
    )

    /// The intent layer's services handoff, owned here — the composition root
    /// — and registered with the App Intents dependency container below, so
    /// intents resolve it via `@Dependency` (no singleton of ours). The launch
    /// installs the store-sharing stack into it via `onServicesReady`.
    let intentServices = IntentServices()

    /// The launch engine, built in `didFinishLaunching` (launching
    /// `.undetermined`, since the UIScene lifecycle can't yet tell a user launch
    /// from a headless wake here) and handed to `RootView` via `WhereApp`.
    private(set) var launcher: LifecycleRunner<WhereSession>!

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
        // Launch `.undetermined`: under the UIScene lifecycle
        // `application.applicationState` reads `.background` here even for a
        // user tap, so we can't honestly tell a headless wake from a user launch
        // yet. The runner drives only the background-safe steps (servicing a
        // possible location wake we can't yet rule out) and builds no view tree;
        // `RootView`'s `enterForeground()` promotes it to `.userForeground` once
        // a scene genuinely activates. A genuine headless wake simply stays
        // `.undetermined` — on a participating iPhone or iPad the queued
        // location event is delivered through the `CLLocationManager` installed
        // below, so no launch-state guess is needed to service it. Catalyst has
        // no local recorder to service.
        //
        // Start the process-wide ambient log sources. The durable sink belongs
        // to whichever scope the user ends up in (`WhereScope` opens it), and
        // no scope exists this early, so these — and everything else logged
        // before the launch resolves one — reach OSLog only.
        WhereLaunch.startAmbientLogging(on: .shared)
        // `initializePrerequisites` installs the CLLocationManager
        // synchronously on participating iPhone/iPad hosts (so a queued location
        // event isn't lost) and registers the foreground-notification presenter;
        // Catalyst skips the location half. The rest (store open, etc.) runs as
        // async steps off this synchronous launch path.
        // `onServicesReady` fires from the `start-session` step on every session
        // (re)start: derive the App Intents stack from the launch's services —
        // same store, attribution, and clock; GPS-free — and install it, so
        // the launch's open is the process's *only* store open and an intent
        // can never race it with a second container over the same file (two
        // containers racing to create it on a fresh install is how the launch
        // once failed). Intents that fire earlier park in
        // `IntentServices.current()` until this lands; the derivation can't
        // fail, so nothing can strand them parked.
        // The other half of that handoff: when the app logs out of a scope,
        // release the derived stack too. Nothing else would, and holding it
        // would keep the abandoned store alive past the point the next login
        // opens another over the same file.
        model.onLoggedOut = { [intentServices] in await intentServices.clear() }
        launcher = WhereLaunch
            .makeLauncher(model: model, reason: .undetermined) { [intentServices] in
                await intentServices.install(.forIntents(sharingStoreOf: $0))
            }
        Task { [model] in
            await launcher.run()
            // Index the tracked regions into Spotlight (a search for a region
            // name surfaces Where and its day-count query) through the stack
            // installed above, off the launch critical path. Indexing a
            // handful of items is cheap and idempotent.
            //
            // Never from demo mode: the Spotlight index is device state that
            // outlives the process, and a demo must leave nothing behind. (The
            // launch now waits on the user's choice, so by the time this runs
            // it's known.)
            guard !model.isInDemoMode else { return }
            await RegionSpotlightIndexer.indexRegions(resolving: intentServices)
        }
        return true
    }
}
