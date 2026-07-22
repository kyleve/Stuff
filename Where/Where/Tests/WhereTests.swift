import Testing
import UIKit
@testable import Where
import WhereUI

/// App-target smoke tests: the production shell wiring from `WhereApp` through
/// `AppDelegate` into `RootView`.
@MainActor
struct WhereAppTests {
    @Test func appDelegateBuildsLaunchStateForRootView() {
        let delegate = AppDelegate()
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Mirrors `WhereApp.body`: `RootView(model: appDelegate.model,
        // launchState: appDelegate.launchState)`.
        _ = RootView(model: delegate.model, launchState: delegate.launchState)
        // The launch starts headless under the UIScene lifecycle (it can't
        // tell a user launch from a headless wake at `didFinishLaunching`);
        // the launch task parks before its foreground tail until `RootView`
        // reports a genuinely active scene. This holds regardless of whether
        // the test host happens to be foregrounded.
        #expect(!delegate.launchState.sceneHasBeenActive)

        // This `didFinishLaunching` also re-registered the intent-services
        // handoff with `AppDependencyManager` (the host app's own launch
        // registered first). That's tolerated, but its resolution can't be
        // asserted here: `@Dependency` fatal-errors outside the intent perform
        // flow, so the registration→resolution plumbing is device-verified
        // only (see the comment in `AppDelegate`).
    }
}
