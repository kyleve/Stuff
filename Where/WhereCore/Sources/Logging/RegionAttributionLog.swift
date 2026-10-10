import PeriscopeCore

@LogScope("RegionAttribution")
enum RegionAttributionLog {
    enum SpanName: Hashable { case rebuild }

    @LogEvent("tracked-regions-read-failed", level: .warning, version: 2)
    struct TrackedRegionsReadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to read tracked regions for attributor rebuild: \(error.description)"
        }
    }
}
