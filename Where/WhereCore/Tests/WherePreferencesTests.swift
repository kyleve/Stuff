import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func yearViewModeDefaultsToCalendar() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())

        #expect(preferences.yearViewMode == .calendar)
    }

    @Test func yearViewModeRoundTripsThroughARecreatedPreferencesValue() {
        let store = InMemoryKeyValueStore()
        let first = WherePreferences(store: store)
        first.yearViewMode = .heatmap

        let recreated = WherePreferences(store: store)

        #expect(recreated.yearViewMode == .heatmap)
    }

    @Test func unknownYearViewModeFallsBackToCalendar() {
        let store = InMemoryKeyValueStore()
        store.set("future-mode", forKey: "where.yearViewMode")
        let preferences = WherePreferences(store: store)

        #expect(preferences.yearViewMode == .calendar)
    }

    @Test func resetClearsYearViewMode() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.yearViewMode = .breakdown

        preferences.reset()

        #expect(preferences.yearViewMode == .calendar)
    }
}
