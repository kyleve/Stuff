import PeriscopeCore

@LogScope("LocationNamer")
enum LocationNamerLog {
    @LogEvent(
        "unusable-coordinate",
        level: .warning,
        message: "Skipped a place-name lookup for an unusable coordinate",
    )
    struct UnusableCoordinate {}

    @LogEvent("geocode-failed", level: .warning, version: 2)
    struct GeocodeFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Reverse geocoding failed: \(error.description)"
        }
    }
}
