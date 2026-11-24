import Foundation
@testable import RegionKit
import Testing

/// The drift guard behind the About screen's data credits: every bundled
/// region's geometry is attributed to exactly one source, so regenerating the
/// catalog can't quietly ship uncredited data.
struct RegionDataSourceTests {
    private let catalog = RegionCatalog.shared

    @Test func everyCatalogRegionIsCoveredExactlyOnce() {
        let covered = RegionDataSource.all.flatMap(\.nodes)
        #expect(Set(covered) == Set(catalog.nodes))
        // Set equality alone would accept a region claimed by two sources.
        #expect(covered.count == catalog.nodes.count)
    }

    @Test func noSourceClaimsARegionOutsideTheCatalog() {
        let known = Set(catalog.all)
        for source in RegionDataSource.all {
            #expect(source.regions.allSatisfy { known.contains($0) })
        }
    }

    @Test func aRegionFromAnUnknownSourceStaysUncovered() throws {
        // The failure this guard exists for: a new non-US region lands in the
        // catalog and no source claims it. It must not be swept into the
        // hand-drawn bucket as an "everything else" fallback.
        let unattributed = Region(unchecked: "atlantis")
        let catalog = try RegionCatalog(manifest: Data("""
        [{"id":"atlantis","name":"Atlantis","kind":"country","isLoggable":true,"geometry":{"file":"atlantis.geojson"}}]
        """.utf8))
        let covered = RegionDataSource.sources(coveringRegionsIn: catalog).flatMap(\.regions)
        #expect(!covered.contains(unattributed))
    }

    @Test func creditsTheCensusBoundaryFilesForUSStates() throws {
        let source = try #require(RegionDataSource.all.first { $0.regions.contains(.california) })
        #expect(source.name.contains("TIGER/Line"))
        #expect(source.fidelity == .authoritative)
        #expect(source.license == .publicDomain("US Government works — 17 U.S.C. § 105"))
        #expect(source.sourceURL != nil)
        #expect(source.nodes.count == 53)
        #expect(source.nodes.contains { $0.id.rawValue == "united-states" && $0.region == nil })
    }

    @Test func creditsStatisticsCanadaForCountryAndSubdivisions() throws {
        let source = try #require(RegionDataSource.all.first { $0.regions.contains(.canada) })
        #expect(source.nodes.count == 14)
        #expect(source.fidelity == .authoritative)
        #expect(source.license == .openGovernmentCanada)
        #expect(source.licenseURL != nil)
    }

    @Test func marksTheHandDrawnOutlineAsApproximate() throws {
        let source = try #require(RegionDataSource.all
            .first { $0.regions.contains(.europeanUnion) })
        #expect(source.regions == [.europeanUnion])
        #expect(source.fidelity == .approximate)
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
