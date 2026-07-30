import PeriscopeCore

/// Structured events for `RegionAttributor`'s per-region geometry load. Missing
/// or corrupt bundled geometry is a programmer error, so those cases log at
/// `.fault` (paired with a debug `assertionFailure`); the region id rides on
/// `externalID` so the tooling can pull every event about one region.
enum RegionAttributorLog: LogEvent {
    /// Names the loader's timed spans. Building an attributor parses one GeoJSON
    /// file per region, which is the most expensive thing RegionKit does — and it
    /// happens on the launch's critical path (and again whenever the tracked set
    /// changes), so both the whole load and each region's share of it are timed.
    ///
    /// `description` is spelled out because ``loadRegion(_:)`` carries a region:
    /// reflection would render it `loadRegion(RegionKit.Region(rawValue: "us-CA"))`,
    /// which is both unreadable and a Swift-internal shape in a name the tools
    /// group timings by.
    enum SpanName: Hashable, CustomStringConvertible {
        /// Loading every region an attributor was built for.
        case loadPolygons
        /// One region's GeoJSON read + decode, so a slow load attributes to the
        /// region whose geometry is heavy rather than to the set.
        case loadRegion(Region)

        var description: String {
            switch self {
                case .loadPolygons: "loadPolygons"
                case let .loadRegion(region): "loadRegion(\(region.rawValue))"
            }
        }
    }

    /// The manifest names a geometry file the bundle doesn't contain.
    case missingGeometry(region: Region)
    /// The region's GeoJSON decoded to zero polygons.
    case emptyPolygons(region: Region)
    /// The region's GeoJSON failed to decode.
    case decodeFailed(region: Region, description: String)
    /// Finished loading polygons for `regionCount` regions.
    case loaded(regionCount: Int)

    static let eventName = "RegionAttributor"

    var level: LogLevel {
        switch self {
            case .missingGeometry, .emptyPolygons, .decodeFailed: .fault
            case .loaded: .info
        }
    }

    var message: String {
        switch self {
            case let .missingGeometry(region):
                "Missing bundled GeoJSON for region \(region.rawValue)"
            case let .emptyPolygons(region):
                "Region \(region.rawValue) decoded no polygons"
            case let .decodeFailed(region, description):
                "Failed to decode bundled GeoJSON for region \(region.rawValue): \(description)"
            case let .loaded(regionCount):
                "Loaded region polygons for \(regionCount) region(s)"
        }
    }

    var externalID: String? {
        switch self {
            case let .missingGeometry(region), let .emptyPolygons(region),
                 let .decodeFailed(region, _):
                region.regionURL.absoluteString
            case .loaded:
                nil
        }
    }
}
