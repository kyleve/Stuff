import PeriscopeCore

/// Structured events for `CreditCatalog`'s bundled-manifest load. A missing or
/// unparseable `credits.json` is a programmer error (corrupt bundled resource),
/// so those cases log at `.fault` to match the paired `assertionFailure` — and
/// it matters beyond a blank screen: the manifest is how the app discharges its
/// attribution obligations.
enum CreditCatalogLog: LogEvent {
    /// The bundled `credits.json` manifest is absent from the bundle.
    case missingManifest
    /// The manifest decoded successfully into `creditCount` entries.
    case loaded(creditCount: Int)
    /// The manifest was present but could not be decoded.
    case decodeFailed(description: String)

    static let eventName = "CreditCatalog"

    var level: LogLevel {
        switch self {
            case .missingManifest, .decodeFailed: .fault
            case .loaded: .info
        }
    }

    var message: String {
        switch self {
            case .missingManifest:
                "Missing required bundled credits.json manifest"
            case let .loaded(creditCount):
                "Loaded credit catalog with \(creditCount) credit(s)"
            case let .decodeFailed(description):
                "Failed to decode bundled credits.json: \(description)"
        }
    }
}
