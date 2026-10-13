import PeriscopeCore

/// Classified failures from the planning destination picker.
@LogScope("PlanningRegions")
enum PlanningRegionSelectionModelLog {
    @LogEvent("load-failed", level: .warning, version: 2)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to load tracked regions for planning: \(error.description)"
        }
    }
}
