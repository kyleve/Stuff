import Testing
@testable import WhereUI

struct MainTabSelectionTests {
    @Test func removingElsewhereReturnsItsSelectionToLocations() {
        var selection = MainTabSelection(selected: .elsewhere)
        selection.reconcile(hasElsewhere: true)
        #expect(selection.selected == .elsewhere)
        selection.reconcile(hasElsewhere: false)
        #expect(selection.selected == .locations)
        selection.reconcile(hasElsewhere: true)
        #expect(selection.selected == .locations)
    }

    @Test(arguments: [MainTabSelection.TabID.locations, .year, .settings])
    func availabilityDoesNotSwitchOtherTabs(tab: MainTabSelection.TabID) {
        var selection = MainTabSelection(selected: tab)
        selection.reconcile(hasElsewhere: false)
        #expect(selection.selected == tab)
        selection.reconcile(hasElsewhere: true)
        #expect(selection.selected == tab)
    }
}
