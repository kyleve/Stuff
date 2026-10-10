import PeriscopeCore

@LogScope("LocationForecast")
enum LocationForecastModelLog {
    @LogEvent("load-failed", level: .warning, version: 2)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load the planned stay: \(error.description)"
        }
    }

    @LogEvent("save-failed", level: .warning, version: 2)
    struct SaveFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to save the planned stay: \(error.description)"
        }
    }

    @LogEvent("clear-failed", level: .warning, version: 2)
    struct ClearFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to clear the planned stay: \(error.description)"
        }
    }
}
