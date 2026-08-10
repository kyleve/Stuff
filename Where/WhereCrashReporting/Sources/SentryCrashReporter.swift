import Foundation
import Sentry

/// Starts Sentry crash reporting without exposing its SDK to the application.
public struct SentryCrashReporter: WhereCrashReporting {
    let configuration: Configuration

    public init(dsn: String, debug: Bool) {
        configuration = Configuration(dsn: dsn, debug: debug)
    }

    public func start() {
        guard CrashReportingProcess.shouldStart(
            environment: ProcessInfo.processInfo.environment,
        ) else { return }
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.debug = configuration.debug
        }
    }

    struct Configuration: Equatable {
        let dsn: String
        let debug: Bool
    }
}
