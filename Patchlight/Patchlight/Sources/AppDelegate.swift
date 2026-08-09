import UIKit
#if DEBUG
    import Inspector
#endif

/// Selects production or Inspector once, then forwards process callbacks.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let runtime: any PatchlightApplicationRuntime

    override init() {
        #if DEBUG
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                preconditionFailure("Patchlight has no bundle identifier")
            }
            let modeController = InspectorModeController(
                applicationIdentifier: bundleIdentifier,
            )
            if !modeController.completePendingStoreErasures(fileManager: .default) {
                modeController.enterInspectorOnNextLaunch()
            }
            if modeController.nextLaunch == .inspector {
                runtime = PatchlightInspectorApplicationRuntime(modeController: modeController)
            } else {
                runtime = RegularApplicationRuntime()
            }
        #else
            runtime = RegularApplicationRuntime()
        #endif
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        runtime.didFinishLaunching(application: application, options: options)
    }
}
