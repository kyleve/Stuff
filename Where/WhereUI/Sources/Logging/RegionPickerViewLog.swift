import PeriscopeCore

/// Structured events for `RegionPickerView`.
@LogScope("RegionPicker")
enum RegionPickerViewLog {
    @LogEvent("map-geometry-load-failed", level: .warning, version: 2)
    struct MapGeometryLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Region picker failed to load map geometry: \(error.description)"
        }
    }
}
