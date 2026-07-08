import Foundation

/// A geographic region we track presence in for purposes like state-residency
/// audits. Not US-specific: `.canada` and `.europeanUnion` are first-class.
///
/// `.other` is the catch-all for any coordinate that doesn't fall inside the
/// bundled polygons (or for manual day entries where the user wants to
/// represent "somewhere else").
///
/// The `rawValue` strings (`"california"`, `"newYork"`, …) are stable
/// data identifiers used by SwiftData, Codable, and lookup tables. They
/// are **not** user-facing — use `localizedName` for anything the UI
/// renders.
public enum Region: String, Codable, Sendable, Hashable, CaseIterable {
    case california
    case newYork
    case canada
    case europeanUnion
    case other

    /// User-facing name for this region, read from the `RegionKit`
    /// string catalog (`Resources/Localizable.xcstrings`).
    ///
    /// Uses `String(localized:)` with a literal key per case (rather
    /// than `NSLocalizedString` with a runtime-composed
    /// `"region.\(rawValue)"`) so Xcode's string-catalog extraction
    /// tooling can statically find every key. Adding a new region
    /// case is intentionally a compile error here until you add a
    /// matching string catalog entry.
    public var localizedName: String {
        switch self {
            case .california:
                String(localized: "region.california", bundle: .module)
            case .newYork:
                String(localized: "region.newYork", bundle: .module)
            case .canada:
                String(localized: "region.canada", bundle: .module)
            case .europeanUnion:
                String(localized: "region.europeanUnion", bundle: .module)
            case .other:
                String(localized: "region.other", bundle: .module)
        }
    }

    /// Where this region's boundary geometry comes from. This is the
    /// single source of truth that drives `RegionAttributor`'s bundle
    /// load (and the developer region-map viewer) — collapsing what used
    /// to be a hardcoded region list plus a separate name table. Like
    /// `localizedName`, the exhaustive `switch` makes adding a `Region`
    /// case a compile error until its geometry source is declared here.
    public var geometrySource: GeometrySource {
        switch self {
            case .california: .usStateFeature(name: "California")
            case .newYork: .usStateFeature(name: "New York")
            case .canada: .bundledFile
            case .europeanUnion: .bundledFile
            case .other: .none
        }
    }

    /// How a `Region`'s boundary polygons are sourced from bundled
    /// GeoJSON in `Resources/`.
    public enum GeometrySource: Hashable, Sendable {
        /// A feature in the shared `us-states.geojson`, matched by its
        /// Census `properties.NAME` (the associated value). The name is a
        /// **data identifier** for matching the bundled file, never shown
        /// to the user — user-facing labels go through `localizedName`.
        /// Adding a US state needs no new bundled file.
        case usStateFeature(name: String)
        /// A dedicated `<Region.rawValue>.geojson` file (e.g. `.canada`,
        /// `.europeanUnion`).
        case bundledFile
        /// No bundled polygons — the catch-all `.other`.
        case none
    }
}
