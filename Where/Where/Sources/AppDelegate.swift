import os
import UIKit
import WhereUI

/// Owns the app's single `WhereModel` and wires location up at process launch
/// rather than from a SwiftUI view's `.task`.
///
/// This matters for background relaunch: when CoreLocation relaunches the app
/// after termination (a significant location change or visit), there's no UI,
/// so a view's `.task` is not a reliable hook. `didFinishLaunching` always
/// runs, so building the controller (and `CLLocationManager`) here lets
/// CoreLocation deliver the pending event, and re-starting GPS continues
/// background tracking when the user intends it and Always is granted.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = WhereModel()

    private let logger = Logger(subsystem: "com.stuff.where", category: "AppDelegate")

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        if launchOptions?[.location] != nil {
            logger.info("Relaunched by CoreLocation for a background location event")
        }

        // Build the controller + CLLocationManager synchronously so a location
        // event delivered during launch isn't lost, then (re)register
        // monitoring and reconcile tracking off the main thread.
        model.bootstrap()
        Task { await model.start() }
        return true
    }
}
