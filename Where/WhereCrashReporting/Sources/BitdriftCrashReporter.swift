import Capture
import Foundation

/// Starts Bitdrift Capture without exposing its SDK to the application.
public struct BitdriftCrashReporter: WhereCrashReporting {
    let configuration: Configuration

    public init(apiKey: String) {
        configuration = Configuration(apiKey: apiKey)
    }

    public func start() {
        guard CrashReportingProcess.shouldStart(
            environment: ProcessInfo.processInfo.environment,
        ) else { return }
        Logger.start(
            withAPIKey: configuration.apiKey,
            sessionStrategy: .fixed(),
        )
    }

    struct Configuration: Equatable {
        let apiKey: String
    }
}
