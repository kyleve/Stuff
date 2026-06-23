import LifecycleKit
import Testing
import UIKit
@testable import Where
import WhereUI

/// App-target smoke tests: launch-reason mapping and the production shell wiring
/// from `WhereApp` through `AppDelegate` into `RootView`.
@MainActor
struct WhereAppTests {
    @Test func lifecycleReasonMapsLocationLaunchOption() {
        let options: [UIApplication.LaunchOptionsKey: Any] = [.location: true]
        #expect(WhereLaunch.lifecycleReason(from: options) == .background(.location))
    }

    @Test func lifecycleReasonDefaultsToUserForeground() {
        #expect(WhereLaunch.lifecycleReason(from: nil) == .userForeground)
        #expect(WhereLaunch.lifecycleReason(from: [:]) == .userForeground)
    }

    @Test func appDelegateBuildsLauncherForRootView() {
        let delegate = AppDelegate()
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Mirrors `WhereApp.body`: `RootView(model: appDelegate.model, launcher:
        // appDelegate.launcher)`.
        _ = RootView(model: delegate.model, launcher: delegate.launcher)
        #expect(delegate.launcher.reason == .userForeground)
    }

    @Test func appDelegateMapsBackgroundLocationRelaunch() {
        let delegate = AppDelegate()
        let options: [UIApplication.LaunchOptionsKey: Any] = [.location: true]
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: options)

        #expect(delegate.launcher.reason == .background(.location))
        _ = RootView(model: delegate.model, launcher: delegate.launcher)
    }
}
