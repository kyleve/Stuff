import PeriscopeCore

/// Structured events for `ManualDayView`.
@LogScope("ManualDayView")
enum ManualDayViewLog {
    @LogEvent("region-grouping-load-failed", level: .warning)
    struct RegionGroupingLoadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Manual-day form couldn't load regions for grouping: \(description)"
        }
    }
}
