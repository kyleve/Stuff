import Foundation
import Sentry

/// Starts the process-wide crash reporter without exposing the vendor SDK to
/// the application target.
@MainActor
public enum WhereCrashReporting {
    public static func start(dsn: String, debug: Bool) {
        guard shouldStart(environment: ProcessInfo.processInfo.environment) else { return }
        let configuration = configuration(dsn: dsn, debug: debug)
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.debug = configuration.debug
        }
    }

    static func configuration(dsn: String, debug: Bool) -> Configuration {
        Configuration(dsn: dsn, debug: debug)
    }

    static func shouldStart(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    struct Configuration: Equatable {
        let dsn: String
        let debug: Bool
    }
}
