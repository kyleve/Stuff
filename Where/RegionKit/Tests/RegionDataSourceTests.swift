import Foundation
@testable import RegionKit
import Testing

/// The drift guard behind the About screen's data credits: every bundled
/// region's geometry is attributed to exactly one source, so regenerating the
/// catalog can't quietly ship uncredited data.
struct RegionDataSourceTests {
    private let catalog = RegionCatalog.shared

    @Test func everyCatalogRegionIsCoveredExactlyOnce() {
        let covered = RegionDataSource.all.flatMap(\.regions)
        #expect(Set(covered) == Set(catalog.all))
        // Set equality alone would accept a region claimed by two sources.
        #expect(covered.count == catalog.all.count)
    }

    @Test func noSourceClaimsARegionOutsideTheCatalog() {
        let known = Set(catalog.all)
        for source in RegionDataSource.all {
            #expect(source.regions.allSatisfy { known.contains($0) })
        }
    }

    @Test func aRegionFromAnUnknownSourceStaysUncovered() {
        // The failure this guard exists for: a new non-US region lands in the
        // catalog and no source claims it. It must not be swept into the
        // hand-drawn bucket as an "everything else" fallback.
        let unattributed = Region(unchecked: "atlantis")
        let catalog = RegionCatalog(entries: [
            RegionCatalog.Entry(
                region: unattributed,
                name: "Atlantis",
                localizationKey: nil,
                geometryFile: "atlantis.geojson",
            ),
        ])
        let covered = RegionDataSource.sources(coveringRegionsIn: catalog).flatMap(\.regions)
        #expect(!covered.contains(unattributed))
    }

    @Test func creditsTheCensusBoundaryFilesForUSStates() throws {
        let source = try #require(RegionDataSource.all.first { $0.regions.contains(.california) })
        #expect(source.name == "US Census Bureau Cartographic Boundary Files")
        #expect(source.fidelity == .authoritative)
        #expect(source.license == .publicDomain("US Government works — 17 U.S.C. § 105"))
        #expect(source.sourceURL != nil)
        // Credited separately from the publisher: the bundled files came via a
        // conversion, and saying otherwise would overstate the provenance.
        #expect(source.obtainedFromURL != nil)
    }

    @Test func marksTheHandDrawnOutlinesAsApproximate() throws {
        let source = try #require(RegionDataSource.all.first { $0.regions.contains(.canada) })
        #expect(source.regions.contains(.europeanUnion))
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

    @Test func dropsSourcesThatCoverNothing() {
        // An empty catalog credits nobody rather than listing bare source names.
        #expect(RegionDataSource.sources(coveringRegionsIn: RegionCatalog(entries: [])).isEmpty)
    }
}
