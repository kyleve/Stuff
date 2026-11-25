import Foundation
@testable import RegionKit
import Testing

struct RegionAttributorTests {
    let attributor = RegionAttributor.shared

    // MARK: - California

    @Test func sanFrancisco_isCalifornia() {
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        #expect(attributor.region(at: sf) == .california)
    }

    @Test func losAngeles_isCalifornia() {
        let la = Coordinate(latitude: 34.0522, longitude: -118.2437)
        #expect(attributor.region(at: la) == .california)
    }

    @Test func renoIsOutsideCalifornia() {
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        #expect(attributor.region(at: reno) != .california)
    }

    @Test func tijuanaIsOutsideCalifornia() {
        let tijuana = Coordinate(latitude: 32.5149, longitude: -117.0382)
        #expect(attributor.region(at: tijuana) != .california)
    }

    // MARK: - New York

    @Test func newYorkCity_isNewYork() {
        let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
        #expect(attributor.region(at: nyc) == .newYork)
    }

    @Test func buffalo_isNewYork() {
        let buffalo = Coordinate(latitude: 42.8864, longitude: -78.8784)
        #expect(attributor.region(at: buffalo) == .newYork)
    }

    @Test func newark_isOutsideNewYork() {
        let newark = Coordinate(latitude: 40.7357, longitude: -74.1724)
        #expect(attributor.region(at: newark) != .newYork)
    }

    // MARK: - Canada

    @Test func toronto_isCanada() {
        let toronto = Coordinate(latitude: 43.6532, longitude: -79.3832)
        #expect(attributor.region(at: toronto) == .canada)
    }

    @Test func montreal_isCanada() {
        let montreal = Coordinate(latitude: 45.5017, longitude: -73.5673)
        #expect(attributor.region(at: montreal) == .canada)
    }

    @Test func buffalo_isNotCanada() {
        let buffalo = Coordinate(latitude: 42.8864, longitude: -78.8784)
        #expect(attributor.region(at: buffalo) != .canada)
    }

    // MARK: - European Union

    @Test func paris_isEuropeanUnion() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        #expect(attributor.region(at: paris) == .europeanUnion)
    }

    @Test func berlin_isEuropeanUnion() {
        let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
        #expect(attributor.region(at: berlin) == .europeanUnion)
    }

    @Test func london_isOutsideEuropeanUnion() {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        #expect(attributor.region(at: london) != .europeanUnion)
    }

    // MARK: - Other

    @Test func chicago_isOther() {
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)
        #expect(attributor.region(at: chicago) == .other)
    }

    @Test func tokyo_isOther() {
        let tokyo = Coordinate(latitude: 35.6762, longitude: 139.6503)
        #expect(attributor.region(at: tokyo) == .other)
    }

    // MARK: - On-demand subset loading

    /// An attributor loads and attributes only the regions it's built for, so a
    /// coordinate inside an untracked region falls through to `.other`.
    @Test func attributorLoadsOnlyItsRegions() {
        let californiaOnly = RegionAttributor(for: [.california])
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
        #expect(californiaOnly.region(at: sf) == .california)
        // New York isn't loaded, so a NYC coordinate falls through to `.other`.
        #expect(californiaOnly.region(at: nyc) == .other)
    }

    /// Any catalog state — not just the historical four — can be tracked, since
    /// each region loads from its own bundled file.
    @Test func attributorCanTrackAnyCatalogState() throws {
        let illinois = try #require(Region(rawValue: "us-IL"))
        let attributor = RegionAttributor(for: [illinois])
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)
        #expect(attributor.region(at: chicago) == illinois)
    }

    @Test func trackedProvinceAndCountrySelectOneWinner() throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let ontario = Region(unchecked: "ca-ON")
        let toronto = Coordinate(latitude: 43.6532, longitude: -79.3832)
        let montreal = Coordinate(latitude: 45.5017, longitude: -73.5673)
        let country = rectangle(region: .canada, west: -90, east: -60)
        let province = rectangle(region: ontario, west: -85, east: -75)
        for order in [[country, province], [province, country]] {
            let both = RegionAttributor(regionPolygons: order, catalog: catalog)
            #expect(both.region(at: toronto) == ontario)
            #expect(both.region(at: montreal) == .canada)
            #expect(both.distance(to: .canada, from: toronto) == 0)
            let boundary = try #require(both.distanceToBoundary(of: .canada, from: toronto))
            #expect(boundary > 0)
        }
        let parentOnly = RegionAttributor(regionPolygons: [country], catalog: catalog)
        #expect(parentOnly.region(at: toronto) == .canada)
        #expect(parentOnly.distance(to: ontario, from: toronto) == nil)
        let childOnly = RegionAttributor(regionPolygons: [province], catalog: catalog)
        #expect(childOnly.region(at: toronto) == ontario)
        #expect(childOnly.region(at: montreal) == .other)
        #expect(RegionAttributor(regionPolygons: [], catalog: catalog)
            .region(at: toronto) == .other)
    }

    @Test func priorityAppliesAfterEliminatingMatchingAncestors() throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let ontario = Region(unchecked: "ca-ON")
        let coordinate = Coordinate(latitude: 44, longitude: -80)
        let parent = rectangle(region: .canada, west: -90, east: -60)
        let child = rectangle(region: ontario, west: -85, east: -75)
        let unrelated = rectangle(region: .newYork, west: -83, east: -72)
        let beforeChild = RegionAttributor(
            regionPolygons: [parent, unrelated, child],
            catalog: catalog,
        )
        let afterChild = RegionAttributor(
            regionPolygons: [child, unrelated, parent],
            catalog: catalog,
        )
        #expect(beforeChild.region(at: coordinate) == .newYork)
        #expect(afterChild.region(at: coordinate) == ontario)
        let disjointHierarchy = RegionAttributor(
            regionPolygons: [unrelated, child],
            catalog: catalog,
        )
        #expect(disjointHierarchy.region(at: coordinate) == .newYork)
    }

    @Test func confidenceRespectsUnrelatedPriorityAtOverlappingEdges() throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let ontario = Region(unchecked: "ca-ON")
        let justOutsideNewYork = Coordinate(latitude: 44, longitude: -83.001)
        let province = rectangle(region: ontario, west: -85, east: -75)
        let unrelated = rectangle(region: .newYork, west: -83, east: -72)
        let first = RegionAttributor(regionPolygons: [unrelated, province], catalog: catalog)
        let last = RegionAttributor(regionPolygons: [province, unrelated], catalog: catalog)
        let nearBoundary = try #require(first.matchWithBoundaryDistance(at: justOutsideNewYork))
        let farBoundary = try #require(last.matchWithBoundaryDistance(at: justOutsideNewYork))
        #expect(nearBoundary.region == ontario)
        #expect(farBoundary.region == ontario)
        #expect(nearBoundary.boundaryDistance < 100)
        #expect(farBoundary.boundaryDistance > 100_000)
    }

    @Test(arguments: [-75.001, -74.999])
    func crossingProvinceCanRestoreItsParentsPriority(longitude: Double) throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let overlap = RegionAttributor(regionPolygons: [
            rectangle(region: .canada, west: -90, east: -60),
            rectangle(region: .newYork, west: -83, east: -72),
            rectangle(region: Region(unchecked: "ca-ON"), west: -85, east: -75),
        ], catalog: catalog)
        let match = try #require(overlap.matchWithBoundaryDistance(at: Coordinate(
            latitude: 44,
            longitude: longitude,
        )))
        #expect(match.region == (longitude < -75 ? Region.newYork : .canada))
        #expect(match.boundaryDistance < 100)
    }

    @Test func loadingTrackedCoverageReadsEachPhysicalMemberOnce() throws {
        let catalog = try RegionHierarchyFixture.catalog()
        let internalCountry = try JSONDecoder().decode(
            Region.self,
            from: Data(#""united-states""#.utf8),
        )
        let ontario = Region(unchecked: "ca-ON")
        let fixture = try #require(RegionCatalog.shared.geometryURL(for: .california))
        let inputs: [([Region], [Region])] = [
            ([.california], [.california]),
            ([ontario], [ontario]),
            ([.canada], [ontario]),
            ([.canada, ontario], [ontario]),
            ([ontario, .canada], [ontario]),
        ]
        for (regions, expectedFiles) in inputs {
            var requested: [RegionCatalog.Node.ID] = []
            let attributor = RegionAttributor(
                for: [internalCountry, .other] + regions + regions,
                catalog: catalog,
            ) { node in
                requested.append(node.id)
                return fixture
            }
            #expect(requested.map(\.rawValue) == expectedFiles.map(\.rawValue))
            #expect(attributor.loadedRegions == regions)
        }
    }

    private func rectangle(region: Region, west: Double, east: Double) -> RegionPolygons {
        RegionPolygons(region: region, polygons: [GeoPolygon(vertices: [
            Coordinate(latitude: 42, longitude: west),
            Coordinate(latitude: 42, longitude: east),
            Coordinate(latitude: 50, longitude: east),
            Coordinate(latitude: 50, longitude: west),
        ])])
    }
}
