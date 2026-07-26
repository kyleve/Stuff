import LifecycleKit
import Testing
import UIKit
@testable import Where
import WhereUI

/// App-target smoke tests: the production shell wiring from `WhereApp` through
/// `AppDelegate` into `RootView`.
@MainActor
struct WhereAppTests {
    @Test func appDelegateBuildsLauncherForRootView() {
        let delegate = AppDelegate()
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Mirrors `WhereApp.body`: `RootView(model: appDelegate.model, launcher:
        // appDelegate.launcher)`.
        _ = RootView(model: delegate.model, launcher: delegate.launcher)
        // The app always launches `.undetermined` under the UIScene lifecycle
        // (it can't tell a user launch from a headless wake at
        // `didFinishLaunching`); `RootView`'s `enterForeground()` promotes it to
        // `.userForeground` once a scene activates. This holds regardless of
        // whether the test host happens to be foregrounded.
        #expect(delegate.launcher.reason == .undetermined)

        // This `didFinishLaunching` also re-registered the intent-services
        // handoff with `AppDependencyManager` (the host app's own launch
        // registered first). That's tolerated, but its resolution can't be
        // asserted here: `@Dependency` fatal-errors outside the intent perform
        // flow, so the registration→resolution plumbing is device-verified
        // only (see the comment in `AppDelegate`).
    }
}
