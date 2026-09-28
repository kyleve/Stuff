import PeriscopeCore

/// Structured events and spans for `RegionAttributor`.
@LogScope("RegionAttributor")
enum RegionAttributorLog {
    enum SpanName: Hashable, CustomStringConvertible {
        case loadPolygons
        case loadRegion(Region)

        var description: String {
            switch self {
                case .loadPolygons: "loadPolygons"
                case let .loadRegion(region): "loadRegion(\(region.rawValue))"
            }
        }
    }

    @LogEvent("missing-geometry", level: .fault)
    struct MissingGeometry {
        @LogField("region", exposure: .restricted, kind: .location)
        var region: Region
        var message: String {
            "Missing bundled GeoJSON for region \(region.rawValue)"
        }

        var externalID: String? {
            region.regionURL.absoluteString
        }
    }

    @LogEvent("empty-polygons", level: .fault)
    struct EmptyPolygons {
        @LogField("region", exposure: .restricted, kind: .location)
        var region: Region
        var message: String {
            "Region \(region.rawValue) decoded no polygons"
        }

        var externalID: String? {
            region.regionURL.absoluteString
        }
    }

    @LogEvent("decode-failed", level: .fault)
    struct DecodeFailed {
        @LogField("region", exposure: .restricted, kind: .location)
        var region: Region
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to decode bundled GeoJSON for region \(region.rawValue): \(description)"
        }

        var externalID: String? {
            region.regionURL.absoluteString
        }
    }

    @LogEvent("loaded")
    struct Loaded {
        @LogField("region_count", exposure: .shareable, kind: .count)
        var regionCount: Int
        var message: String {
            "Loaded region polygons for \(regionCount) region(s)"
        }
    }
}
