import PeriscopeCore

/// Structured events for drawable geometry loads.
@LogScope("RegionGeometryCatalog")
public enum RegionGeometryCatalogLog {
    public enum SpanName: Hashable, Sendable, CustomStringConvertible {
        case buildSourceOutlines
        case loadRegionOutlines(Region)

        public var description: String {
            switch self {
                case .buildSourceOutlines: "buildSourceOutlines"
                case let .loadRegionOutlines(region):
                    "loadRegionOutlines(\(region.rawValue))"
            }
        }
    }

    @LogEvent("load-failed", level: .warning)
    public struct LoadFailed {
        @LogField("kind", exposure: .restricted, kind: .technicalState)
        public var kind: String

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        public var description: String

        public var message: String {
            "Region map viewer failed to load \(kind) geometry: \(description)"
        }
    }

    @LogEvent("region-load-failed", level: .fault)
    public struct RegionLoadFailed {
        @LogField("region", exposure: .restricted, kind: .location)
        public var region: Region

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        public var description: String

        public var message: String {
            "Failed to load drawable outlines for \(region.rawValue): \(description)"
        }

        public var externalID: String? {
            region.regionURL.absoluteString
        }
    }
}
