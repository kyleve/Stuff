import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct SceneNavigationModelTests {
    @Test func anUnselectedLocationsSceneKeepsItsNavigationEmpty() {
        let navigation = SceneNavigationModel()
        #expect(navigation.locations.selectedRegion == nil)
        #expect(navigation.locations.browsePath.isEmpty)
        #expect(navigation.locations.compactColumn == .sidebar)
    }

    @Test func repeatedRegionSelectionPreservesHistoryAndDrillInState() {
        let navigation = SceneNavigationModel.Locations()
        navigation.select(region: .california)
        let month = CalendarDay(year: 2026, month: 2, day: 1)
        navigation.calendar.reveal(month: month)
        navigation.detailPath.append(month)
        navigation.select(region: .california)
        #expect(navigation.detailPath.count == 1)
        #expect(navigation.calendar.displayedMonth == month)
        navigation.select(region: .newYork)
        #expect(navigation.detailPath.isEmpty)
        #expect(navigation.calendar.displayedMonth == month)
    }

    @Test func settingsSelectionRetainsSearchAndResetsOnlyAnExplicitlyChangedDestination() {
        let navigation = SceneNavigationModel.Settings()
        navigation.searchText = "appearance"
        navigation.selectedRoute = SettingsRoute(.appearance)
        navigation.path.append(SettingsRoute(.about))
        navigation.selectedRoute = SettingsRoute(.appearance)
        #expect(navigation.path.count == 1)
        navigation.selectedRoute = SettingsRoute(.about)
        #expect(navigation.path.isEmpty)
        #expect(navigation.searchText == "appearance")
    }
}
