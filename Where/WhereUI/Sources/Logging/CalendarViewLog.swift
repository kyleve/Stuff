import PeriscopeCore

/// Structured events for `CalendarView`'s degraded presentation states.
@LogScope("CalendarView")
enum CalendarViewLog {
    @LogEvent("opened-without-report", level: .warning)
    struct OpenedWithoutReport {
        @LogField(exposure: .restricted, kind: .technicalState)
        var loadState: String

        var message: String {
            "Calendar opened without a year report (loadState: \(loadState))"
        }
    }

    @LogEvent("layout-failed", level: .warning, version: 2)
    struct LayoutFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Calendar layout failed: \(error.description)"
        }
    }
}
