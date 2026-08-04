import PeriscopeCore

/// Structured events for drawable geometry loads. A failed developer-viewer
/// load is degraded-but-handled and logs at `.warning`; a missing production
/// artwork resource is a bundled-data invariant and logs at `.fault`. Public
/// because the UI consumers live above RegionKit and emit through
/// ``RegionLog/geometryCatalog``.
public enum RegionGeometryCatalogLog: LogEvent {
    /// Names the catalog's timed span.
    /// `Sendable` is spelled out because this is a `public` nested type — unlike
    /// the internal `SpanName`s elsewhere, it gets no inferred conformance, and
    /// `LogEvent.SpanName` requires one.
    public enum SpanName: Hashable, Sendable, CustomStringConvertible {
        /// The `.source` build: decoding *every* catalog region's GeoJSON at full
        /// authored fidelity, which is far heavier than attribution's tracked
        /// subset. Runs once per process behind the cache actor, so this span is
        /// what the viewer's first toggle to source actually costs.
        case buildSourceOutlines
        /// The first request for one region's drawable outlines. Later requests
        /// reuse the per-region cache.
        case loadRegionOutlines(Region)

        public var description: String {
            switch self {
                case .buildSourceOutlines: "buildSourceOutlines"
                case let .loadRegionOutlines(region):
                    "loadRegionOutlines(\(region.rawValue))"
            }
        }
    }

    /// Loading the outlines for a `RegionGeometryKind` failed.
    case loadFailed(kind: String, description: String)
    /// Loading the bundled outlines used by region-specific artwork failed.
    /// Bundled geometry is a programmer-owned invariant, so this is a fault.
    case regionLoadFailed(region: Region, description: String)

    public static let eventName = "RegionGeometryCatalog"

    public var level: LogLevel {
        switch self {
            case .loadFailed: .warning
            case .regionLoadFailed: .fault
        }
    }

    public var message: String {
        switch self {
            case let .loadFailed(kind, description):
                "Region map viewer failed to load \(kind) geometry: \(description)"
            case let .regionLoadFailed(region, description):
                "Failed to load drawable outlines for \(region.rawValue): \(description)"
        }
    }

    public var externalID: String? {
        switch self {
            case .loadFailed:
                nil
            case let .regionLoadFailed(region, _):
                region.regionURL.absoluteString
        }
    }
}
