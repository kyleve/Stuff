import PeriscopeCore

/// Structured events for the app launch sequence (`WhereLaunch` /
/// `WhereBootstrap`), including the process-global log-store bootstrap.
enum WhereLaunchLog: LogEvent {
    /// Names the launch spans — one bounded span per launch step.
    enum SpanName: Hashable {
        case step
    }

    case runnerCreated(reason: String)
    case servicesAssembled
    /// Assembling the service layer (store open + `WhereServices.make`) failed;
    /// the `open-store` step surfaces it and the launch parks in `.failed`.
    case servicesAssemblyFailed(description: String)
    /// The durable log store opened and attached to `Periscope.shared`, having
    /// pruned `prunedEventCount` events past the retention window.
    case loggingStoreReady(prunedEventCount: Int)
    /// Opening the durable log store failed; logging continues through the
    /// OSLog sink only, with no persisted history this launch.
    case loggingStoreUnavailable(description: String)

    static let eventName = "WhereLaunch"

    var level: LogLevel {
        switch self {
            case .runnerCreated, .servicesAssembled, .loggingStoreReady:
                .info
            case .servicesAssemblyFailed, .loggingStoreUnavailable:
                .error
        }
    }

    var message: String {
        switch self {
            case let .runnerCreated(reason):
                "Lifecycle runner created (reason: \(reason))"
            case .servicesAssembled:
                "WhereServices assembled"
            case let .servicesAssemblyFailed(description):
                "Failed to assemble WhereServices: \(description)"
            case let .loggingStoreReady(prunedEventCount):
                "Log store ready (pruned \(prunedEventCount) event(s) past retention)"
            case let .loggingStoreUnavailable(description):
                "Log store unavailable: \(description)"
        }
    }
}
