import PeriscopeCore

@LogScope("RegionAttribution")
enum RegionAttributionLog {
    enum SpanName: Hashable { case rebuild }

    @LogEvent("tracked-regions-read-failed", level: .warning)
    struct TrackedRegionsReadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to read tracked regions for attributor rebuild: \(description)"
        }
    }
}
