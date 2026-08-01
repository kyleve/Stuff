import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct YearModeSelectionTests {
    @Test func restoresThePersistedMode() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.yearViewMode = .heatmap

        let selection = YearModeSelection(preferences: preferences)

        #expect(selection.mode == .heatmap)
    }

    @Test func changingModePersistsAcrossARecreatedSelection() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let first = YearModeSelection(preferences: preferences)
        first.mode = .breakdown

        let recreated = YearModeSelection(preferences: preferences)

        #expect(recreated.mode == .breakdown)
    }

    @Test func explicitInitialModeDoesNotOverwriteThePreference() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.yearViewMode = .heatmap

        let selection = YearModeSelection(preferences: preferences, initialMode: .timeline)

        #expect(selection.mode == .timeline)
        #expect(preferences.yearViewMode == .heatmap)
    }
}
