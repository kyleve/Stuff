import MapKit
@testable import RegionKit
import Testing
@testable import WhereUI

struct RegionArtworkProjectionTests {
    @Test func interiorRingsCutOutTheCardAndMapPolygon() throws {
        let shell = rectangle(west: -82, east: -78, south: 42, north: 46)
        let hole = rectangle(west: -81, east: -79, south: 43, north: 45).reversed()
        let outline = RegionOutline(
            id: .init(title: "Canada", index: 0),
            title: "Canada",
            region: .canada,
            coordinates: shell,
            holes: [Array(hole)],
        )
        let projection = try #require(RegionArtworkProjection(outlines: [outline]))
        let path = projection.path(from: [outline])
        #expect(!path.contains(projection.point(for: Coordinate(latitude: 44, longitude: -80))))
        #expect(path.contains(projection.point(for: Coordinate(latitude: 42.5, longitude: -80))))
        #expect(outline.mapPolygon.interiorPolygons?.count == 1)
    }

    @Test func mapRevealsSmallIslandsAtCloserZoomAndDrawsCountryFirst() {
        let island = RegionOutline(
            id: .init(title: "Province", index: 0),
            title: "Province",
            region: .newYork,
            coordinates: rectangle(west: -80, east: -79.999, south: 44, north: 44.001),
        )
        let country = RegionOutline(
            id: .init(title: "Country", index: 1),
            title: "Country",
            region: .canada,
            coordinates: rectangle(west: -84, east: -78, south: 42, north: 46),
        )
        let map = RegionMapGeometry(outlines: [island, country])
        #expect(map.visible(in: .world, width: 400).map(\.id) == [country.id])
        let zoomed = island.mapPolygon.boundingMapRect.insetBy(dx: -1000, dy: -1000)
        #expect(map.visible(in: zoomed, width: 400).map(\.id) == [country.id, island.id])
        #expect(map.visible(in: zoomed, width: 400, title: "Province").map(\.id) == [island.id])
    }

    @Test func aleutianPolygonDrawsAcrossTheDateline() {
        let outline = RegionOutline(
            id: .init(title: "Island", index: 0),
            title: "Island",
            region: nil,
            coordinates: rectangle(west: 179.9, east: -179.9, south: 51, north: 52),
        )
        #expect(outline.mapPolygon.boundingMapRect.width < MKMapSize.world.width / 100)
    }

    private func rectangle(
        west: Double,
        east: Double,
        south: Double,
        north: Double,
    ) -> [Coordinate] {
        [
            Coordinate(latitude: south, longitude: west),
            Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east),
            Coordinate(latitude: north, longitude: west),
        ]
    }

    @Test(
        arguments: [
            (Region.california, Coordinate(latitude: 37.7749, longitude: -122.4194)),
            (Region.newYork, Coordinate(latitude: 40.7128, longitude: -74.0060)),
        ],
    )
    func projectsRecordedCoordinatesInsideTheirRealOutline(
        region: Region,
        coordinate: Coordinate,
    ) async throws {
        let outlines = await RegionGeometryCatalog.outlines(for: region)
        let projection = try #require(RegionArtworkProjection(outlines: outlines))
        let path = projection.path(from: outlines)

        #expect(path.isEmpty == false)
        #expect(path.contains(projection.point(for: coordinate)))
    }
}
