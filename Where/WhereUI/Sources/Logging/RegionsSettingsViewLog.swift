import PeriscopeCore

/// Structured events for the primary-region editor.
@LogScope("RegionsSettings")
enum RegionsSettingsViewLog {
    @LogEvent("primary-regions-load-failed", level: .warning, version: 2)
    struct PrimaryRegionsLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to load primary regions for editing: \(error.description)"
        }
    }

    @LogEvent("primary-regions-save-failed", level: .warning, version: 2)
    struct PrimaryRegionsSaveFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to save primary region edits: \(error.description)"
        }
    }
}
