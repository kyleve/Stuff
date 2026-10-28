import Foundation

/// Where the bundled region geometry came from, so the app can credit its data
/// the way it credits its code.
///
/// RegionKit owns this because RegionKit owns the GeoJSON: provenance is a fact
/// about the data, not presentation. The values here are proper nouns, URLs, and
/// license terms, so they are deliberately **not** localized — the UI supplies
/// the translated framing around them, and reads ``fidelity`` rather than
/// hard-coding which source happens to be approximate.
///
/// Coverage is derived from ``RegionCatalog`` rather than listed by hand, so a
/// regenerated catalog can't leave a region silently uncredited —
/// `RegionDataSourceTests` fails if one is covered zero times or twice.
public struct RegionDataSource: Sendable, Hashable {
    /// The terms the geometry is available under.
    public enum License: Sendable, Hashable {
        /// A public-domain publication; the associated value names *why* it's in
        /// the public domain. Attribution is still requested for these.
        case publicDomain(String)
        /// Drawn in this repository, so it carries the project's own license
        /// rather than a third party's.
        case originalWork
    }

    /// How closely the geometry follows the real boundary — the difference
    /// between "simplified from a published boundary set" and "sketched well
    /// enough to spot-check with".
    public enum Fidelity: Sendable, Hashable {
        /// Simplified from an authoritative published boundary set.
        case authoritative
        /// A coarse outline with no authoritative basis. Fine for tests and a
        /// rough answer, not for a residency audit.
        case approximate
    }

    /// The boundary set's own name, e.g. "US Census Bureau Cartographic
    /// Boundary Files". Untranslated (see the type note).
    public let name: String
    /// Where the publisher documents the boundary set, when there is one.
    public let sourceURL: URL?
    /// The intermediate the bundled files were actually taken from, when the
    /// data didn't come straight from the publisher — a conversion we credit
    /// separately rather than implying we pulled from the primary source.
    public let obtainedFromURL: URL?
    public let license: License
    public let fidelity: Fidelity
    /// The regions this source provides geometry for, in catalog order.
    public let regions: [Region]

    /// Every data source behind the bundled geometry, each covering at least one
    /// catalog region.
    public static let all: [RegionDataSource] = sources(coveringRegionsIn: .shared)

    /// The sources for `catalog`'s regions. Split out from ``all`` so tests can
    /// drive it with a catalog of their own.
    static func sources(coveringRegionsIn catalog: RegionCatalog) -> [RegionDataSource] {
        // The `us-` prefix is the provenance marker, not a naming coincidence:
        // `generate-regions.rb` mints exactly these ids while splitting the
        // single Census `us-states.geojson` into one file per feature.
        let censusStates = catalog.all.filter { $0.rawValue.hasPrefix(usStateIDPrefix) }
        // Listed explicitly rather than "everything else", so a new non-US
        // region from a real source can't be quietly credited as hand-drawn —
        // it stays uncovered until someone files where it came from.
        let handDrawn = catalog.all.filter { handDrawnIDs.contains($0.rawValue) }

        return [
            RegionDataSource(
                name: "US Census Bureau Cartographic Boundary Files",
                sourceURL: URL(
                    string: "https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html",
                ),
                obtainedFromURL: URL(string: "https://eric.clst.org/tech/usgeojson/"),
                license: .publicDomain("US Government works — 17 U.S.C. § 105"),
                fidelity: .authoritative,
                regions: censusStates,
            ),
            RegionDataSource(
                name: "Hand-drawn outlines",
                sourceURL: nil,
                obtainedFromURL: nil,
                license: .originalWork,
                fidelity: .approximate,
                regions: handDrawn,
            ),
        ]
        .filter { !$0.regions.isEmpty }
    }

    private static let usStateIDPrefix = "us-"
    private static let handDrawnIDs: Set<String> = ["canada", "european-union"]
}
