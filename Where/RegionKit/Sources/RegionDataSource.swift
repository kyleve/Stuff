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
/// `RegionDataSourceTests` checks coverage for each region and purpose.
public struct RegionDataSource: Sendable, Hashable {
    enum Product: String, CaseIterable, Decodable, Hashable {
        case censusTIGER, censusCartographic, statcanDigital, statcanCartographic, original

        var purposes: [RegionGeometryPurpose] {
            switch self {
                case .censusTIGER, .statcanDigital: [.tracking]
                case .censusCartographic, .statcanCartographic: [.display]
                case .original: [.tracking, .display]
            }
        }

        var name: String {
            switch self {
                case .censusTIGER: "US Census Bureau TIGER/Line State and Equivalent Entities"
                case .censusCartographic: "US Census Bureau Cartographic Boundary Files (1:500,000)"
                case .statcanDigital: "Statistics Canada, Census Digital Boundary Files"
                case .statcanCartographic: "Statistics Canada, Census Cartographic Boundary Files"
                case .original: "Hand-drawn outlines"
            }
        }

        func sourceURL(year: Int?) -> URL? {
            guard let year else { return nil }
            switch self {
                case .censusTIGER:
                    return URL(string: "https://www2.census.gov/geo/tiger/TIGER\(year)/STATE/")
                case .censusCartographic:
                    return URL(
                        string: "https://www2.census.gov/geo/tiger/GENZ\(year)/shp/cb_\(year)_us_state_500k.zip",
                    )
                case .statcanDigital, .statcanCartographic:
                    let product = self == .statcanDigital ? "Digital" : "Cartographic"
                    return URL(
                        string: "https://geo.statcan.gc.ca/geo_wa/rest/services/\(year)/\(product)_boundary_files/MapServer/0",
                    )
                case .original:
                    return nil
            }
        }

        var license: License {
            switch self {
                case .censusTIGER,
                     .censusCartographic: .publicDomain("US Government works — 17 U.S.C. § 105")
                case .statcanDigital, .statcanCartographic: .openGovernmentCanada
                case .original: .originalWork
            }
        }
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

    private let product: Product

    /// The publisher’s boundary product name.
    public var name: String {
        product.name
    }

    public var purposes: [RegionGeometryPurpose] {
        product.purposes
            .filter { purpose in nodes.contains { $0.geometry?[purpose].product == product } }
    }

    /// Where the publisher documents the boundary set, when there is one.
    public let sourceURL: URL?
    /// The intermediate the bundled files were actually taken from, when the
    /// data didn't come straight from the publisher — a conversion we credit
    /// separately rather than implying we pulled from the primary source.
    public let obtainedFromURL: URL?
    public var license: License {
        product.license
    }

    public var fidelity: Fidelity {
        product == .original ? .approximate : .authoritative
    }

    /// The regions this source provides geometry for, in catalog order.
    public let nodes: [RegionCatalog.Node]
    public var regions: [Region] {
        nodes.compactMap(\.region)
    }

    /// The published licence terms for the adapted geometry.
    public var licenseURL: URL? {
        switch license {
            case .openGovernmentCanada: URL(
                    string: "https://open.canada.ca/en/open-government-licence-canada",
                )
            case .publicDomain, .originalWork: nil
        }
    }

    /// Every data source behind the bundled geometry, each covering at least one
    /// catalog region.
    public static let all: [RegionDataSource] = sources(coveringRegionsIn: .shared)

    /// The sources for `catalog`'s regions. Split out from ``all`` so tests can
    /// drive it with a catalog of their own.
    static func sources(coveringRegionsIn catalog: RegionCatalog) -> [RegionDataSource] {
        Product.allCases.compactMap { product in
            let nodes = catalog.nodes.filter { node in
                product.purposes.contains { node.geometry?[$0].product == product }
            }
            guard let geometry = nodes.first?.geometry,
                  let purpose = product.purposes.first(where: { geometry[$0].product == product })
            else { return nil }
            return RegionDataSource(
                product: product,
                sourceURL: product.sourceURL(year: geometry[purpose].year),
                obtainedFromURL: nil,
                nodes: nodes,
            )
        }
    }
}
