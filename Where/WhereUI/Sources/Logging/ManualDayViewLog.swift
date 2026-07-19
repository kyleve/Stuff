import PeriscopeCore

/// Structured events for `ManualDayView`, the manual add/edit form. A failure to
/// load regions for grouping degrades to an ungrouped list, so it logs at
/// `.warning`.
enum ManualDayViewLog: LogEvent {
    case regionGroupingLoadFailed(description: String)

    static let eventName = "ManualDayView"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .regionGroupingLoadFailed(description):
                "Manual-day form couldn't load regions for grouping: \(description)"
        }
    }
}
