import PeriscopeCore

/// Structured events for the developer region-map viewer's geometry load. A
/// failed load is degraded-but-handled (the viewer shows an error state), so it
/// logs at `.warning`. Public because the viewer lives in WhereUI, above
/// RegionKit, and emits through ``RegionLog/geometryCatalog``.
public enum RegionGeometryCatalogLog: LogEvent {
    /// Loading the outlines for a `RegionGeometryKind` failed.
    case loadFailed(kind: String, description: String)

    public static let eventName = "RegionGeometryCatalog"

    public var level: LogLevel {
        .warning
    }

    public var message: String {
        switch self {
            case let .loadFailed(kind, description):
                "Region map viewer failed to load \(kind) geometry: \(description)"
        }
    }
}
