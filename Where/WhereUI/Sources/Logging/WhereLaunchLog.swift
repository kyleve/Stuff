import PeriscopeCore

/// Launch/bootstrap events for the `WhereLaunch` flow.
enum WhereLaunchLog: LogEvent {
    /// Names the launch spans — one bounded span per launch step.
    enum SpanName: Hashable {
        case step
    }

    case launchStarted
    case servicesAssembled
    /// Assembling the service layer (store open + `WhereServices.make`) failed;
    /// the launch surfaces it and parks in the terminal `.failed` phase.
    case servicesAssemblyFailed(description: String)
    /// The launch attempt failed. Logged as well as published: a headless
    /// attempt's failure surface is never rendered, so without this the
    /// failure would leave no trace anywhere.
    case launchFailed(description: String)
    /// The reset's erase failed; the session and preferences were left
    /// intact and the launch state parked in the terminal `.failed` phase.
    case resetFailed(description: String)
    /// The durable log store opened and attached to `Periscope.shared`. Fired
    /// as soon as the store is browsable — retention pruning runs after, off the
    /// ready path (see ``historyPruned``).
    case loggingStoreReady
    /// Opening the durable log store failed; logging continues through the
    /// OSLog sink only, with no persisted history this launch.
    case loggingStoreUnavailable(description: String)
    /// Retention pruning finished, removing `prunedEventCount` events past the
    /// window. Runs after ``loggingStoreReady``, so it never delays readiness.
    case historyPruned(prunedEventCount: Int)
    /// Retention pruning failed; the store is still usable (last good history
    /// preserved), it just isn't trimmed this launch.
    case historyPruneFailed(description: String)

    static let eventName = "WhereLaunch"

    var level: LogLevel {
        switch self {
            case .launchStarted, .servicesAssembled, .loggingStoreReady, .historyPruned:
                .info
            // The store is still usable when pruning fails (degraded-but-handled),
            // unlike an outright open failure.
            case .historyPruneFailed:
                .warning
            case .servicesAssemblyFailed, .loggingStoreUnavailable, .launchFailed, .resetFailed:
                .error
        }
    }

    var message: String {
        switch self {
            case .launchStarted:
                "Launch started"
            case .servicesAssembled:
                "WhereServices assembled"
            case let .servicesAssemblyFailed(description):
                "Failed to assemble WhereServices: \(description)"
            case let .launchFailed(description):
                "Launch failed: \(description)"
            case let .resetFailed(description):
                "Erase-and-reset failed: \(description)"
            case .loggingStoreReady:
                "Log store ready"
            case let .loggingStoreUnavailable(description):
                "Log store unavailable: \(description)"
            case let .historyPruned(prunedEventCount):
                "Pruned \(prunedEventCount) log event(s) past retention"
            case let .historyPruneFailed(description):
                "Failed to prune log history: \(description)"
        }
    }
}
