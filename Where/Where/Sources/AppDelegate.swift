import UIKit
#if DEBUG
    import Inspector
#endif

/// Selects one complete application runtime before launch and forwards every
/// process callback to it without branching again.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let runtime: any WhereApplicationRuntime

    override init() {
        #if DEBUG
            guard let applicationIdentifier = Bundle.main.bundleIdentifier else {
                preconditionFailure("Where has no bundle identifier")
            }
            let modeController = InspectorModeController(
                applicationIdentifier: applicationIdentifier,
            )
            runtime = Self.selectRuntime(
                modeController: modeController,
                fileManager: .default,
                regular: {
                    RegularApplicationRuntime(inspectorModeController: modeController)
                },
                inspector: {
                    WhereInspectorApplicationRuntime(modeController: modeController)
                },
            )
        #else
            runtime = RegularApplicationRuntime()
        #endif
        super.init()
    }

    init(runtime: any WhereApplicationRuntime) {
        self.runtime = runtime
        super.init()
    }

    #if DEBUG
        static func selectRuntime(
            modeController: InspectorModeController,
            fileManager: FileManager,
            regular: () -> any WhereApplicationRuntime,
            inspector: () -> any WhereApplicationRuntime,
        ) -> any WhereApplicationRuntime {
            if !modeController.completePendingStoreErasures(fileManager: fileManager) {
                modeController.enterInspectorOnNextLaunch()
            }
            if modeController.nextLaunch == .inspector {
                return inspector()
            } else {
                return regular()
            }
        }
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        runtime.didFinishLaunching(application: application, options: options)
    }
}
