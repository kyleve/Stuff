import PeriscopeCore

/// Structured events for the developer region-map viewer's geometry load. A
/// failed load is degraded-but-handled (the viewer shows an error state), so it
/// logs at `.warning`. Public because the viewer lives in WhereUI, above
/// RegionKit, and emits through ``RegionLog/geometryCatalog``.
public enum RegionGeometryCatalogLog: LogEvent {
    /// Names the catalog's timed span.
    /// `Sendable` is spelled out because this is a `public` nested type — unlike
    /// the internal `SpanName`s elsewhere, it gets no inferred conformance, and
    /// `LogEvent.SpanName` requires one.
    public enum SpanName: Hashable, Sendable {
        /// The `.source` build: decoding *every* catalog region's GeoJSON at full
        /// authored fidelity, which is far heavier than attribution's tracked
        /// subset. Runs once per process behind the cache actor, so this span is
        /// what the viewer's first toggle to source actually costs.
        case buildSourceOutlines
    }

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
