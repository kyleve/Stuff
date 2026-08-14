import PeriscopeCore

/// Structured events and spans for the app launch sequence.
@LogScope("WhereLaunch")
enum WhereLaunchLog {
    enum SpanName: Hashable, CustomStringConvertible {
        case step(LaunchStepID)
        case openLogStore
        case pruneHistory

        var description: String {
            switch self {
                case let .step(id): "step(\(id.rawValue))"
                case .openLogStore: "openLogStore"
                case .pruneHistory: "pruneHistory"
            }
        }
    }

    @LogEvent("runner-created")
    struct RunnerCreated {
        @LogField("reason", exposure: .restricted, kind: .technicalState) var reason: String
        var message: String {
            "Lifecycle runner created (reason: \(reason))"
        }
    }

    @LogEvent("services-assembled", message: "WhereServices assembled")
    struct ServicesAssembled {}

    @LogEvent("services-assembly-failed", level: .error)
    struct ServicesAssemblyFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to assemble WhereServices: \(description)"
        }
    }

    @LogEvent("logging-store-ready", message: "Log store ready")
    struct LoggingStoreReady {}

    @LogEvent("logging-store-unavailable", level: .error)
    struct LoggingStoreUnavailable {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Log store unavailable: \(description)"
        }
    }

    @LogEvent("history-pruned")
    struct HistoryPruned {
        @LogField("expired_event_count", exposure: .shareable, kind: .count)
        var expiredEventCount: Int
        @LogField("overflow_event_count", exposure: .shareable, kind: .count)
        var overflowEventCount: Int
        var message: String {
            "Pruned \(expiredEventCount) log event(s) past retention"
                + " and \(overflowEventCount) past the size cap"
        }
    }

    @LogEvent("history-prune-failed", level: .warning)
    struct HistoryPruneFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to prune log history: \(description)"
        }
    }

    @LogEvent("detached-step-failed", level: .warning)
    struct DetachedStepFailed {
        @LogField("step_id", exposure: .restricted, kind: .identifier) var stepID: String
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Detached launch step '\(stepID)' failed: \(description)"
        }
    }
}
