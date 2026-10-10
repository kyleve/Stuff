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

    @LogEvent("load-failed", level: .warning, version: 2)
    public struct LoadFailed {
        @LogField(exposure: .restricted, kind: .technicalState)
        public var kind: String

        @LogField(exposure: .restricted, kind: .errorDetails)
        public var error: LogError

        public var message: String {
            "Region map viewer failed to load \(kind) geometry: \(error.description)"
        }
    }

    @LogEvent("region-load-failed", level: .fault, version: 2)
    public struct RegionLoadFailed {
        @LogField(exposure: .restricted, kind: .location)
        public var region: Region

        @LogField(exposure: .restricted, kind: .errorDetails)
        public var error: LogError

        public var message: String {
            "Failed to load drawable outlines for \(region.rawValue): \(error.description)"
        }

        public var externalID: String? {
            region.regionURL.absoluteString
        }
    }
}
