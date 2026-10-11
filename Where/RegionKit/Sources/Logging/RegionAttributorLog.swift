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
        @LogField(exposure: .restricted, kind: .location)
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
        @LogField(exposure: .restricted, kind: .location)
        var region: Region
        var message: String {
            "Region \(region.rawValue) decoded no polygons"
        }

        var externalID: String? {
            region.regionURL.absoluteString
        }
    }

    @LogEvent("decode-failed", level: .fault, version: 2)
    struct DecodeFailed {
        @LogField(exposure: .restricted, kind: .location)
        var region: Region
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to decode bundled GeoJSON for region \(region.rawValue): \(error.description)"
        }

        var externalID: String? {
            region.regionURL.absoluteString
        }
    }

    @LogEvent("loaded")
    struct Loaded {
        @LogField(exposure: .shareable, kind: .count)
        var regionCount: Int
        var message: String {
            "Loaded region polygons for \(regionCount) region(s)"
        }
    }
}
