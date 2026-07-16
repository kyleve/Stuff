import PeriscopeCore

/// Structured events for the app launch sequence (`WhereLaunch` /
/// `WhereBootstrap`). Both are successful-milestone `.info` events.
enum WhereLaunchLog: LogEvent {
    /// Names the launch spans — one bounded span per launch step.
    enum SpanName: Hashable {
        case step
    }

    case runnerCreated(reason: String)
    case servicesAssembled

    static let eventName = "WhereLaunch"

    var message: String {
        switch self {
            case let .runnerCreated(reason):
                "Lifecycle runner created (reason: \(reason))"
            case .servicesAssembled:
                "WhereServices assembled"
        }
    }
}
