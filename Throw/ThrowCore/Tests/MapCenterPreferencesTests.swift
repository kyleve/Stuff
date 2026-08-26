import Testing
@testable import ThrowCore

struct MapCenterPreferencesTests {
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
