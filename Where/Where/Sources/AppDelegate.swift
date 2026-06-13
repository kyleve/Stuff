import LifecycleKit
import os
import UIKit
import UserNotifications
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
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = WhereModel()

    /// The launch engine, built in `didFinishLaunching` (where the launch
    /// reason is known) and handed to `RootView` via `WhereApp`.
    private(set) var launcher: LifecycleRunner!

    private let logger = Logger(subsystem: "com.stuff.where", category: "AppDelegate")

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

        // Present logging reminders even while the app is foregrounded so the
        // nudge isn't silently swallowed when the user already has Where open.
        UNUserNotificationCenter.current().delegate = self

        // `initializePrerequisites` installs the CLLocationManager
        // synchronously so a queued location event isn't lost; the rest (store
        // open, etc.) runs as async steps off this synchronous launch path.
        launcher = WhereLaunch.makeLauncher(model: model, reason: reason)
        Task { await launcher.run() }
        return true
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
