import PeriscopeCore

/// Structured events for `ManualDayView`.
@LogScope("ManualDayView")
enum ManualDayViewLog {
    @LogEvent("region-grouping-load-failed", level: .warning, version: 2)
    struct RegionGroupingLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Manual-day form couldn't load regions for grouping: \(error.description)"
        }
    }
}
