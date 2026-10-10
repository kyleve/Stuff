import PeriscopeCore

@LogScope("LocationForecast")
enum LocationForecastModelLog {
    @LogEvent("load-failed", level: .warning)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load the planned stay: \(description)"
        }
    }

    @LogEvent("save-failed", level: .warning)
    struct SaveFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to save the planned stay: \(description)"
        }
    }

    @LogEvent("clear-failed", level: .warning)
    struct ClearFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to clear the planned stay: \(description)"
        }
    }
}
