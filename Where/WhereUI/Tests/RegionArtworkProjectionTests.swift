import RegionKit
import Testing
@testable import WhereUI

struct RegionArtworkProjectionTests {
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
