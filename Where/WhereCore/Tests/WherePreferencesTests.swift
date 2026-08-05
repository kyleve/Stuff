import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func locationForecastsAreShownByDefault() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())

        #expect(preferences.showsLocationForecastsOnLocationsTab)
    }

    @Test func locationForecastVisibilityPersistsAndResets() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())

        preferences.showsLocationForecastsOnLocationsTab = false
        #expect(preferences.showsLocationForecastsOnLocationsTab == false)

        preferences.reset()
        #expect(preferences.showsLocationForecastsOnLocationsTab)
    }
}
