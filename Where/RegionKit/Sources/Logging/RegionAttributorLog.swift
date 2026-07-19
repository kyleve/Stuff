import PeriscopeCore

/// Structured events for `RegionAttributor`'s per-region geometry load. Missing
/// or corrupt bundled geometry is a programmer error, so those cases log at
/// `.fault` (paired with a debug `assertionFailure`); the region id rides on
/// `externalID` so the tooling can pull every event about one region.
enum RegionAttributorLog: LogEvent {
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
