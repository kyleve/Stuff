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
    /// the `resolve-scope` step surfaces it and the launch parks in `.failed`.
    case servicesAssemblyFailed(description: String)
    /// The durable log store opened and became the active scope's sink. Fired
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
    /// A detached (fire-and-forget) launch step failed. Never fatal — the
    /// launch reaches `.ready` regardless and the runner records it on
    /// `detachedFailures` — but it must be visible in logs too, not just on
    /// observable state nothing renders (see `DetachedFailureReporter`).
    case detachedStepFailed(stepID: String, description: String)

    static let eventName = "WhereLaunch"

    var level: LogLevel {
        switch self {
            case .runnerCreated, .servicesAssembled, .loggingStoreReady, .historyPruned:
                .info
            // The store is still usable when pruning fails (degraded-but-handled),
            // unlike an outright open failure. A detached-step failure is the
            // same shape: the launch stays healthy, one best-effort fan-out
            // didn't land.
            case .historyPruneFailed, .detachedStepFailed:
                .warning
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
            case .loggingStoreReady:
                "Log store ready"
            case let .loggingStoreUnavailable(description):
                "Log store unavailable: \(description)"
            case let .historyPruned(prunedEventCount):
                "Pruned \(prunedEventCount) log event(s) past retention"
            case let .historyPruneFailed(description):
                "Failed to prune log history: \(description)"
            case let .detachedStepFailed(stepID, description):
                "Detached launch step '\(stepID)' failed: \(description)"
        }
    }
}
