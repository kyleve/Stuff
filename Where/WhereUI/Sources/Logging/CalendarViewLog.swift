import PeriscopeCore

/// Structured events for `CalendarView`'s degraded presentation states.
@LogScope("CalendarView")
enum CalendarViewLog {
    @LogEvent("opened-without-report", level: .warning)
    struct OpenedWithoutReport {
        @LogField("load_state", exposure: .restricted, kind: .technicalState)
        var loadState: String

        var message: String {
            "Calendar opened without a year report (loadState: \(loadState))"
        }
    }

    @LogEvent("layout-failed", level: .warning)
    struct LayoutFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Calendar layout failed: \(description)"
        }
    }
}
