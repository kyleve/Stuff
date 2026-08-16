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
    private static let logger = WhereLog.root(WhereAppLog.self)

    let runtime: any WhereApplicationRuntime
    private let reportingControllers: [any WhereReportingController]

    override init() {
        let buildEnvironment = WhereBuildEnvironment.current()
        let preferences = WherePreferences(store: UserDefaults.standard)
        let launchConfiguration = preferences.diagnosticReportingConfiguration.effective(
            isDebugBuild: Self.isDebugBuild,
        )
        let client = BitdriftReportingClient(
            apiKey: "GiBBMbsJNDqIM9c5450IEHoYFLt025SQo5kN2Vj6evk3GyILRVl1MWRBWUFLcGso9Qw=",
            environment: ProcessInfo.processInfo.environment,
            writer: BitdriftLogWriter(),
            startupFailure: { error in
                Self.recordDiagnosticProviderFailure(error)
            },
        )
        let reportingController = DiagnosticReportingController(
            launchConfiguration: launchConfiguration,
            client: client,
            logSystem: .shared,
            now: Date.init,
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
                        buildEnvironment: buildEnvironment,
                        preferences: preferences,
                        effectiveDiagnosticReportingConfiguration: launchConfiguration,
                        applyRemoteLogging: applyRemoteLogging,
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
            let regularRuntime = RegularApplicationRuntime(
                buildEnvironment: buildEnvironment,
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: launchConfiguration,
                applyRemoteLogging: applyRemoteLogging,
            )
            runtime = regularRuntime
        #endif
        client.setStartupFailureHandler {
            [weak model = (runtime as? RegularApplicationRuntime)?.model] error in
            Self.recordDiagnosticProviderFailure(error)
            let message = String(describing: error)
            Task {
                await reportingController.providerDidFail()
                model?.diagnosticReporting.recordRuntimeFailure(message)
            }
        }
        super.init()
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    private static func recordDiagnosticProviderFailure(_ error: any Error) {
        logger(attachments: [.error(error, name: "provider-startup-error")]) {
            .diagnosticProviderStartupFailed
        }
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
