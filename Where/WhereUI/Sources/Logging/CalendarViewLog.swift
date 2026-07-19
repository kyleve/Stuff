import PeriscopeCore

/// Structured events for `CalendarView`'s layout. Both cases are
/// degraded-but-handled presentation states, so they log at `.warning`.
enum CalendarViewLog: LogEvent {
    case openedWithoutReport(loadState: String)
    case layoutFailed(description: String)

    static let eventName = "CalendarView"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .openedWithoutReport(loadState):
                "Calendar opened without a year report (loadState: \(loadState))"
            case let .layoutFailed(description):
                "Calendar layout failed: \(description)"
        }
    }
}
