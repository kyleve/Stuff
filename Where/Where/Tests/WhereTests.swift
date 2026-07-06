import LifecycleKit
import Testing
import UIKit
@testable import Where
import WhereUI

/// App-target smoke tests: launch-reason mapping and the production shell wiring
/// from `WhereApp` through `AppDelegate` into `RootView`.
@MainActor
struct WhereAppTests {
    @Test func backgroundLaunchStateMapsToLocationRelaunch() {
        #expect(WhereLaunch.lifecycleReason(from: .background) == .background(.location))
    }

    @Test func foregroundLaunchStatesMapToUserForeground() {
        #expect(WhereLaunch.lifecycleReason(from: .active) == .userForeground)
        #expect(WhereLaunch.lifecycleReason(from: .inactive) == .userForeground)
    }

    @Test func appDelegateBuildsLauncherForRootView() {
        let delegate = AppDelegate()
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Mirrors `WhereApp.body`: `RootView(model: appDelegate.model, launcher:
        // appDelegate.launcher)`.
        _ = RootView(model: delegate.model, launcher: delegate.launcher)
        // The reason now derives from the live launch-time application state
        // (the mapping itself is covered above); assert the delegate wired it
        // from that state rather than hardcoding a value.
        #expect(
            delegate.launcher.reason
                == WhereLaunch.lifecycleReason(from: UIApplication.shared.applicationState),
        )
    }
}
