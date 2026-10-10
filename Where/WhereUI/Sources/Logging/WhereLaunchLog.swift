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
        @LogField(exposure: .restricted, kind: .technicalState) var reason: String
        var message: String {
            "Lifecycle runner created (reason: \(reason))"
        }
    }

    @LogEvent("services-assembled", message: "WhereServices assembled")
    struct ServicesAssembled {}

    @LogEvent("services-assembly-failed", level: .error, version: 2)
    struct ServicesAssemblyFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to assemble WhereServices: \(error.description)"
        }
    }

    @LogEvent("logging-store-ready", message: "Log store ready")
    struct LoggingStoreReady {}

    @LogEvent("logging-store-unavailable", level: .error, version: 2)
    struct LoggingStoreUnavailable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Log store unavailable: \(error.description)"
        }
    }

    @LogEvent("history-pruned")
    struct HistoryPruned {
        @LogField(exposure: .shareable, kind: .count)
        var expiredEventCount: Int
        @LogField(exposure: .shareable, kind: .count)
        var overflowEventCount: Int
        var message: String {
            "Pruned \(expiredEventCount) log event(s) past retention"
                + " and \(overflowEventCount) past the size cap"
        }
    }

    @LogEvent("history-prune-failed", level: .warning, version: 2)
    struct HistoryPruneFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to prune log history: \(error.description)"
        }
    }

    @LogEvent("detached-step-failed", level: .warning, version: 2)
    struct DetachedStepFailed {
        @LogField(exposure: .restricted, kind: .identifier) var stepID: String
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Detached launch step '\(stepID)' failed: \(error.description)"
        }
    }
}
