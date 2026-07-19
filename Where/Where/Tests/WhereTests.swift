import CoreLocation
import LifecycleKit
import Testing
import UIKit
@testable import Where
import WhereUI

/// App-target smoke tests: launch-reason mapping and the production shell wiring
/// from `WhereApp` through `AppDelegate` into `RootView`.
@MainActor
struct WhereAppTests {
    @Test func backgroundLaunchWithAlwaysAuthMapsToLocationRelaunch() {
        #expect(
            WhereLaunch.lifecycleReason(from: .background, locationAuthorization: .authorizedAlways)
                == .background(.location),
        )
    }

    @Test func backgroundLaunchWithoutAlwaysAuthIsNotAttributedToLocation() {
        // Where can only be woken headless by an Always-authorized location
        // event, so any other authorization is an honest `.other` background.
        for status in [
            CLAuthorizationStatus.authorizedWhenInUse,
            .denied,
            .restricted,
            .notDetermined,
        ] {
            #expect(
                WhereLaunch.lifecycleReason(from: .background, locationAuthorization: status)
                    == .background(.other),
            )
        }
    }

    @Test func foregroundLaunchStatesMapToUserForeground() {
        // A foreground launch is user-visible regardless of authorization.
        #expect(
            WhereLaunch.lifecycleReason(from: .active, locationAuthorization: .notDetermined)
                == .userForeground,
        )
        #expect(
            WhereLaunch.lifecycleReason(from: .inactive, locationAuthorization: .authorizedAlways)
                == .userForeground,
        )
    }

    @Test func appDelegateBuildsLauncherForRootView() {
        let delegate = AppDelegate()
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Mirrors `WhereApp.body`: `RootView(model: appDelegate.model, launcher:
        // appDelegate.launcher)`.
        _ = RootView(model: delegate.model, launcher: delegate.launcher)
        // The hosted test app runs in the foreground, so the launch always maps
        // to `.userForeground` (the background/authorization branches are
        // covered by the pure-mapping tests above).
        #expect(delegate.launcher.reason == .userForeground)

        // This `didFinishLaunching` also re-registered the intent-services
        // handoff with `AppDependencyManager` (the host app's own launch
        // registered first). That's tolerated, but its resolution can't be
        // asserted here: `@Dependency` fatal-errors outside the intent perform
        // flow, so the registration→resolution plumbing is device-verified
        // only (see the comment in `AppDelegate`).
    }
}
