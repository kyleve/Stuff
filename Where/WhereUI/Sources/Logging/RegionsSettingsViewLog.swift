import PeriscopeCore

/// Structured events for the primary-region editor.
@LogScope("RegionsSettings")
enum RegionsSettingsViewLog {
    @LogEvent("primary-regions-load-failed", level: .warning)
    struct PrimaryRegionsLoadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load primary regions for editing: \(description)"
        }
    }

    @LogEvent("primary-regions-save-failed", level: .warning)
    struct PrimaryRegionsSaveFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to save primary region edits: \(description)"
        }
    }
}
