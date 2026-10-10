import PeriscopeCore

/// Structured events for `RegionPickerView`.
@LogScope("RegionPicker")
enum RegionPickerViewLog {
    @LogEvent("map-geometry-load-failed", level: .warning)
    struct MapGeometryLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Region picker failed to load map geometry: \(description)"
        }
    }
}
