import UIKit
import WhereCrashReporting
#if DEBUG
    import Inspector
#endif

/// Selects one complete application runtime before launch and forwards every
/// process callback to it without branching again.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let runtime: any WhereApplicationRuntime
    private let crashReporters: [any WhereCrashReporting]

    override init() {
        let buildEnvironment = WhereBuildEnvironment.current()
        crashReporters = [
            SentryCrashReporter(
                dsn: "https://b6d0c35a9bf66d188439e9a6e2022733@o4511883510677504.ingest.us.sentry.io/4511883519983616",
                debug: Self.sentryDebugLoggingEnabled,
            ),
            BitdriftCrashReporter(
                apiKey: "GiBBMbsJNDqIM9c5450IEHoYFLt025SQo5kN2Vj6evk3GyILRVl1MWRBWUFLcGso9Qw=",
            ),
        ]
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
                    RegularApplicationRuntime(
                        buildEnvironment: buildEnvironment,
                        inspectorModeController: modeController,
                    )
                },
                inspector: {
                    WhereInspectorApplicationRuntime(
                        buildEnvironment: buildEnvironment,
                        modeController: modeController,
                    )
                },
            )
        #else
            runtime = RegularApplicationRuntime(buildEnvironment: buildEnvironment)
        #endif
        super.init()
    }

    init(runtime: any WhereApplicationRuntime) {
        self.runtime = runtime
        crashReporters = []
        super.init()
    }

    init(
        runtime: any WhereApplicationRuntime,
        crashReporters: [any WhereCrashReporting],
    ) {
        self.runtime = runtime
        self.crashReporters = crashReporters
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
        for crashReporter in crashReporters {
            crashReporter.start()
        }
        return runtime.didFinishLaunching(application: application, options: options)
    }

    private static var sentryDebugLoggingEnabled: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}
