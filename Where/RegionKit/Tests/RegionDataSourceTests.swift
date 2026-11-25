import Foundation
@testable import RegionKit
import Testing

/// The drift guard behind the About screen's data credits: every bundled
/// region's geometry is attributed to exactly one source, so regenerating the
/// catalog can't quietly ship uncredited data.
struct RegionDataSourceTests {
    private let catalog = RegionCatalog.shared

    @Test func everyCatalogRegionIsCreditedOnceForEachPurpose() {
        #expect(RegionDataSource.all.count == 5)
        for purpose in RegionGeometryPurpose.allCases {
            let covered = RegionDataSource.all.filter { $0.purposes.contains(purpose) }
                .flatMap(\.regions)
            #expect(Set(covered) == Set(catalog.all))
            #expect(covered.count == 66)
        }
    }

    @Test func creditsBothCensusProductsAndTheirOwnVintage() throws {
        let sources = RegionDataSource.all.filter { $0.regions.contains(.california) }
        #expect(sources.count == 2)
        for source in sources {
            #expect(source.fidelity == .authoritative)
            #expect(source.licenseURL == nil)
            #expect(source.license == .publicDomain("US Government works — 17 U.S.C. § 105"))
            #expect(source.nodes.count == 52)
            #expect(source.nodes.allSatisfy { $0.parentID?.rawValue == "united-states" })
            let url = try #require(source.sourceURL)
            let role = try #require(source.purposes.first)
            let year = try #require(source.nodes.first?.geometry?[role].year)
            #expect(url.absoluteString.contains(String(year)))
            switch role {
                case .tracking:
                    #expect(source.name.contains("TIGER/Line") && url.path.contains("TIGER"))
                case .display:
                    #expect(source.name.contains("Cartographic") && url.path.contains("500k"))
            }
        }
    }

    @Test func creditsBothCanadianProductsAndTheirOwnServices() throws {
        let canada = try #require(catalog.node(id: .init(rawValue: "canada")))
        let members = catalog.children(of: canada)
        let sources = RegionDataSource.all.filter { $0.license == .openGovernmentCanada }
        #expect(sources.count == 2 && members.count == 13)
        for source in sources {
            #expect(source.nodes == members)
            #expect(source.fidelity == .authoritative)
            #expect(source.licenseURL != nil)
            let url = try #require(source.sourceURL)
            let role = try #require(source.purposes.first)
            let year = try #require(source.nodes.first?.geometry?[role].year)
            let product = role == .tracking ? "Digital" : "Cartographic"
            #expect(url.path == "/geo_wa/rest/services/\(year)/\(product)_boundary_files/MapServer")
        }
    }

    @Test func marksTheHandDrawnOutlineAsApproximate() throws {
        let source = try #require(RegionDataSource.all
            .first { $0.regions.contains(.europeanUnion) })
        #expect(source.regions == [.europeanUnion])
        #expect(Set(source.purposes) == Set(RegionGeometryPurpose.allCases))
        #expect(source.fidelity == .approximate)
        #expect(source.licenseURL == nil)
        #expect(source.license == .originalWork)
        #expect(source.sourceURL == nil)
    }

    @Test func listsRegionsInCatalogOrder() {
        for source in RegionDataSource.all {
            let expected = catalog.all.filter { source.regions.contains($0) }
            #expect(source.regions == expected)
        }
    }

    @Test func dropsSourcesThatCoverNothing() throws {
        // An empty catalog credits nobody rather than listing bare source names.
        let empty = try RegionCatalog(manifest: Data("[]".utf8))
        #expect(RegionDataSource.sources(coveringRegionsIn: empty).isEmpty)
    }
}
