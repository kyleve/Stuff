import Testing
@testable import ThrowCore

struct GeographyModelsTests {
    @Test(
        arguments: [
            DetailVisibilityCase(level: .wide, limit: 240),
            DetailVisibilityCase(level: .standard, limit: 80),
            DetailVisibilityCase(level: .local, limit: 20),
            DetailVisibilityCase(level: .neighborhood, limit: 8),
        ],
    )
    func detailLevelUsesAnInclusiveExplicitRadiusLimit(testCase: DetailVisibilityCase) throws {
        let limit = try NauticalMiles(value: testCase.limit)
        let beyondLimit = try NauticalMiles(value: testCase.limit + 0.000_001)

        #expect(testCase.level.includes(mapRadius: limit))
        #expect(testCase.level.includes(mapRadius: beyondLimit) == false)
    }

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
                detailLevel: .wide,
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
                detailLevel: .wide,
                bounds: bounds,
                coordinates: [
                    GeoCoordinate(latitude: 0, longitude: 0),
                    GeoCoordinate(latitude: 2, longitude: 0),
                ],
            )
        }
    }

    struct DetailVisibilityCase {
        let level: GeographyDetailLevel
        let limit: Double
    }
}
