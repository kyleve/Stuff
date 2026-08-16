import PeriscopeCore

@LogScope("LocationNamer")
enum LocationNamerLog {
    @LogEvent(
        "unusable-coordinate",
        level: .warning,
        message: "Skipped a place-name lookup for an unusable coordinate",
    )
    struct UnusableCoordinate {}

    @LogEvent("geocode-failed", level: .warning)
    struct GeocodeFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Reverse geocoding failed: \(description)"
        }
    }
}
