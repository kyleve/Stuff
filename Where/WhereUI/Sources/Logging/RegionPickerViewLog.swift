import PeriscopeCore

/// Structured events for `RegionPickerView`. A geometry-load failure leaves the
/// map in an honest error state (not a blank map), so it logs at `.warning`.
enum RegionPickerViewLog: LogEvent {
    case mapGeometryLoadFailed(description: String)

    static let eventName = "RegionPicker"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .mapGeometryLoadFailed(description):
                "Region picker failed to load map geometry: \(description)"
        }
    }
}
