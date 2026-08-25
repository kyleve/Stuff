import Testing
@testable import ThrowCore

struct GeographyModelsTests {
    @Test func boundsRejectAnAntimeridianWrappingPath() {
        #expect(throws: GeographyDataError.invalidArchive) {
            try GeographicBounds(
                southLatitude: -10,
                westLongitude: 170,
                northLatitude: 10,
                eastLongitude: -170,
            )
        }
    }

    @Test func polylineRequiresAtLeastTwoCoordinates() throws {
        let bounds = try GeographicBounds(
            southLatitude: 0,
            westLongitude: 0,
            northLatitude: 0,
            eastLongitude: 0,
        )
        #expect(throws: GeographyDataError.invalidArchive) {
            try GeographicPolyline(
                kind: .coastline,
                minimumZoomTenths: 0,
                scaleRank: 0,
                bounds: bounds,
                coordinates: [GeoCoordinate(latitude: 0, longitude: 0)],
            )
        }
    }

    @Test func polylineRequiresBoundsToContainItsCoordinates() throws {
        let bounds = try GeographicBounds(
            southLatitude: 0,
            westLongitude: 0,
            northLatitude: 1,
            eastLongitude: 1,
        )
        #expect(throws: GeographyDataError.invalidArchive) {
            try GeographicPolyline(
                kind: .river,
                minimumZoomTenths: 0,
                scaleRank: 0,
                bounds: bounds,
                coordinates: [
                    GeoCoordinate(latitude: 0, longitude: 0),
                    GeoCoordinate(latitude: 2, longitude: 0),
                ],
            )
        }
    }
}
