import Foundation

/// Where the bundled region geometry came from, so the app can credit its data
/// the way it credits its code.
///
/// RegionKit owns this because RegionKit owns the polygons: provenance is a fact
/// about the data, not presentation. The values here are proper nouns, URLs, and
/// license terms, so they are deliberately **not** localized — the UI supplies
/// the translated framing around them, and reads ``fidelity`` rather than
/// hard-coding which source happens to be approximate.
///
/// Coverage is derived from ``RegionCatalog`` rather than listed by hand, so a
/// regenerated catalog can't leave a region silently uncredited —
/// `RegionDataSourceTests` fails if one is covered zero times or twice.
public struct RegionDataSource: Sendable, Hashable {
    enum Publisher: String, Decodable {
        case census, statcan, original
    }

    /// The terms the geometry is available under.
    public enum License: Sendable, Hashable {
        /// A public-domain publication; the associated value names *why* it's in
        /// the public domain. Attribution is still requested for these.
        case publicDomain(String)
        /// Drawn in this repository, so it carries the project's own license
        /// rather than a third party's.
        case originalWork
        case openGovernmentCanada
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

    /// The publisher’s boundary product name. Untranslated (see the type note).
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
    public let nodes: [RegionCatalog.Node]
    public var regions: [Region] {
        nodes.compactMap(\.region)
    }

    /// The published licence terms for the adapted geometry.
    public var licenseURL: URL? {
        guard license == .openGovernmentCanada else { return nil }
        return URL(string: "https://open.canada.ca/en/open-government-licence-canada")
    }

    /// Every data source behind the bundled geometry, each covering at least one
    /// catalog region.
    public static let all: [RegionDataSource] = sources(coveringRegionsIn: .shared)

    /// The sources for `catalog`'s regions. Split out from ``all`` so tests can
    /// drive it with a catalog of their own.
    static func sources(coveringRegionsIn catalog: RegionCatalog) -> [RegionDataSource] {
        let files = catalog.nodes.filter { $0.geometryFile != nil }
        let census = files.filter { $0.source == .census }
        let statcan = files.filter { $0.source == .statcan }
        return [
            RegionDataSource(
                name: "US Census Bureau TIGER/Line State and Equivalent Entities",
                sourceURL: census.first?.sourceYear.flatMap {
                    URL(string: "https://www2.census.gov/geo/tiger/TIGER\($0)/STATE/")
                },
                obtainedFromURL: nil,
                license: .publicDomain("US Government works — 17 U.S.C. § 105"),
                fidelity: .authoritative,
                nodes: census,
            ),
            RegionDataSource(
                name: "Statistics Canada, Census Cartographic Boundary Files",
                sourceURL: statcan.first?.sourceYear.flatMap {
                    URL(
                        string: "https://geo.statcan.gc.ca/geo_wa/rest/services/\($0)/Cartographic_boundary_files/MapServer",
                    )
                },
                obtainedFromURL: nil,
                license: .openGovernmentCanada,
                fidelity: .authoritative,
                nodes: statcan,
            ),
            RegionDataSource(
                name: "Hand-drawn outlines",
                sourceURL: nil,
                obtainedFromURL: nil,
                license: .originalWork,
                fidelity: .approximate,
                nodes: files.filter { $0.source == .original },
            ),
        ].filter { !$0.nodes.isEmpty }
    }
}
