import PeriscopeCore
import UIKit
import WhereCore
import WhereCrashReporting
import WhereUI
#if DEBUG
    import Inspector
#endif

/// Selects one complete application runtime before launch and forwards every
/// process callback to it without branching again.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let runtime: any WhereApplicationRuntime
    private let reportingControllers: [any WhereReportingController]

    override init() {
        let preferences = WherePreferences(store: UserDefaults.standard)
        let launchConfiguration = preferences.diagnosticReportingConfiguration.effective(
            isDebugBuild: Self.isDebugBuild,
        )
        let client = BitdriftReportingClient(
            apiKey: "GiBBMbsJNDqIM9c5450IEHoYFLt025SQo5kN2Vj6evk3GyILRVl1MWRBWUFLcGso9Qw=",
            environment: ProcessInfo.processInfo.environment,
            writer: BitdriftLogWriter(),
            startupFailure: { _ in },
        )
        let reportingController = DiagnosticReportingController(
            launchConfiguration: launchConfiguration,
            client: client,
            logSystem: .shared,
        )
        reportingControllers = [reportingController]
        let applyRemoteLogging: DiagnosticReportingSettingsModel.ApplyRemoteLogging = {
            [reportingController] configuration, revision in
            try await reportingController.applyRemoteLogging(configuration, revision: revision)
        }
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
                        preferences: preferences,
                        effectiveDiagnosticReportingConfiguration: launchConfiguration,
                        applyRemoteLogging: applyRemoteLogging,
                        inspectorModeController: modeController,
                    )
                },
                inspector: {
                    WhereInspectorApplicationRuntime(modeController: modeController)
                },
            )
            if let regularRuntime = runtime as? RegularApplicationRuntime {
                client.setStartupFailureHandler { [weak model = regularRuntime.model] message in
                    Task { await reportingController.providerDidFail() }
                    model?.diagnosticReporting.recordRuntimeFailure(message)
                }
            }
        #else
            let regularRuntime = RegularApplicationRuntime(
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: launchConfiguration,
                applyRemoteLogging: applyRemoteLogging,
            )
            client.setStartupFailureHandler { [weak model = regularRuntime.model] message in
                Task { await reportingController.providerDidFail() }
                model?.diagnosticReporting.recordRuntimeFailure(message)
            }
            runtime = regularRuntime
        #endif
        super.init()
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    init(runtime: any WhereApplicationRuntime) {
        self.runtime = runtime
        reportingControllers = []
        super.init()
    }

    init(
        runtime: any WhereApplicationRuntime,
        reportingControllers: [any WhereReportingController],
    ) {
        self.runtime = runtime
        self.reportingControllers = reportingControllers
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
        for reportingController in reportingControllers {
            reportingController.start()
        }
        return runtime.didFinishLaunching(application: application, options: options)
    }
}
