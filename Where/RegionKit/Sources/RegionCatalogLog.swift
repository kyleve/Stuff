import PeriscopeCore

/// Structured events for `RegionCatalog`'s bundled-manifest load. A missing or
/// unparseable `regions.json` is a programmer error (corrupt bundled resource),
/// so those cases log at `.fault` to match the paired `assertionFailure`.
enum RegionCatalogLog: LogEvent {
    /// The bundled `regions.json` manifest is absent from the bundle.
    case missingManifest
    /// The manifest decoded successfully into `regionCount` entries.
    case loaded(regionCount: Int)
    /// The manifest was present but could not be decoded.
    case decodeFailed(description: String)

    static let eventName = "RegionCatalog"

    var level: LogLevel {
        switch self {
            case .missingManifest, .decodeFailed: .fault
            case .loaded: .info
        }
    }

    var message: String {
        switch self {
            case .missingManifest:
                "Missing required bundled regions.json manifest"
            case let .loaded(regionCount):
                "Loaded region catalog with \(regionCount) region(s)"
            case let .decodeFailed(description):
                "Failed to decode bundled regions.json: \(description)"
        }
    }
}
