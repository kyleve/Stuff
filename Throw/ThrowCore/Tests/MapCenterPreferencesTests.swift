import Testing
@testable import ThrowCore

struct MapCenterPreferencesTests {
    @Test func mapCenterOffsetAcceptsOnlyFiveMileStepsWithinItsEditingRange() throws {
        let offset = try MapCenterOffset(
            eastNauticalMiles: -50,
            northNauticalMiles: 45,
        )

        #expect(offset.eastNauticalMiles == -50)
        #expect(offset.northNauticalMiles == 45)
        for invalidValue in [-55.0, 7, 50.1, .infinity, .nan] {
            #expect(throws: ThrowValidationError.self) {
                try MapCenterOffset(
                    eastNauticalMiles: invalidValue,
                    northNauticalMiles: 0,
                )
            }
        }
    }

    @Test func northPoleUsesTheLastValidLatitudeBand() throws {
        let coordinate = try GeoCoordinate(latitude: 90, longitude: 0)
        let region = MapRegionID(containing: coordinate)

        #expect(region.latitudeBand == 89)
        #expect(region.longitudeBand == 0)
        #expect(
            try MapRegionID(
                latitudeBand: region.latitudeBand,
                longitudeBand: region.longitudeBand,
            ) == region,
        )
    }

    @Test func southPoleUsesTheFirstValidLatitudeBand() throws {
        let coordinate = try GeoCoordinate(latitude: -90, longitude: 0)
        let region = MapRegionID(containing: coordinate)

        #expect(region.latitudeBand == -90)
        #expect(region.longitudeBand == 0)
        #expect(
            try MapRegionID(
                latitudeBand: region.latitudeBand,
                longitudeBand: region.longitudeBand,
            ) == region,
        )
    }

    @Test func positiveDatelineCanonicalizesToTheNegativeDatelineBand() throws {
        let positiveCoordinate = try GeoCoordinate(latitude: 0, longitude: 180)
        let negativeCoordinate = try GeoCoordinate(latitude: 0, longitude: -180)
        let positive = MapRegionID(containing: positiveCoordinate)
        let negative = MapRegionID(containing: negativeCoordinate)

        #expect(positive == negative)
        #expect(positive.longitudeBand == -180)
        #expect(
            try MapRegionID(
                latitudeBand: positive.latitudeBand,
                longitudeBand: positive.longitudeBand,
            ) == positive,
        )
    }

    @Test func fixedCenterIsSharedWithinCoarseRegion() throws {
        let sanFrancisco = try GeoCoordinate(latitude: 37.77, longitude: -122.42)
        let oakland = try GeoCoordinate(latitude: 37.80, longitude: -122.27)
        let shiftedCenter = try GeoCoordinate(latitude: 37.77, longitude: -121.90)
        let preferences = MapCenterPreferences.defaultValue.setting(
            center: shiftedCenter,
            for: sanFrancisco,
        )

        #expect(preferences.center(for: oakland) == shiftedCenter)
    }

    @Test func differentRegionStartsAtItsObserver() throws {
        let sanFrancisco = try GeoCoordinate(latitude: 37.77, longitude: -122.42)
        let shiftedCenter = try GeoCoordinate(latitude: 37.77, longitude: -121.90)
        let newYork = try GeoCoordinate(latitude: 40.71, longitude: -74.01)
        let preferences = MapCenterPreferences.defaultValue.setting(
            center: shiftedCenter,
            for: sanFrancisco,
        )

        #expect(preferences.center(for: newYork) == newYork)
    }

    @Test func resetRemovesOnlyCurrentRegion() throws {
        let sanFrancisco = try GeoCoordinate(latitude: 37.77, longitude: -122.42)
        let newYork = try GeoCoordinate(latitude: 40.71, longitude: -74.01)
        let westCenter = try GeoCoordinate(latitude: 37.77, longitude: -121.90)
        let eastCenter = try GeoCoordinate(latitude: 40.71, longitude: -73.70)
        let preferences = MapCenterPreferences.defaultValue
            .setting(center: westCenter, for: sanFrancisco)
            .setting(center: eastCenter, for: newYork)
            .resetting(for: sanFrancisco)

        #expect(preferences.center(for: sanFrancisco) == sanFrancisco)
        #expect(preferences.center(for: newYork) == eastCenter)
    }
}
