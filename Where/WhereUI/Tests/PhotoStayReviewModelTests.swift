import RegionKit
import Testing
@testable import WhereUI

@MainActor
struct PhotoStayReviewModelTests {
    @Test func recommendationsPreserveExplicitPicks() {
        let selection = PrimaryRegionDraft(available: [.california, .newYork])
        selection.suggestRegions(from: [.newYork: 2, .california: 1, .other: 9])
        #expect(selection.suggestedRegions == [.newYork, .california])
        #expect(selection.selectedRegions.isEmpty)
        selection.toggle(.california)
        selection.suggestRegions(from: [.newYork: 3])
        #expect(selection.selectedRegions == [.california])
        selection.suggestRegions(from: [.california: 2, .newYork: 2])
        #expect(selection.suggestedRegions == [.california, .newYork])
    }

    @Test func recommendationsMoveBetweenShortcutsCountriesAndPicks() {
        let draft = PrimaryRegionDraft(available: [.ontario, .newYork, .california])
        draft.suggestRegions(from: [.newYork: 2, .ontario: 5])
        let picker = RegionPickerModel(draft: draft, usedThisYear: [.ontario, .california])
        #expect(picker.browse.suggested == [.ontario, .newYork])
        #expect(picker.browse.usedThisYear == [.california])
        picker.expandedCountries = [.canada]
        #expect(picker.browse.suggested == [.newYork])
        #expect(picker.browse.countryGroups.first { $0.id == .canada }?.regions == [.ontario])
        draft.toggle(.ontario)
        picker.expandedCountries = []
        #expect(picker.selectedNewestFirst == [.ontario])
        #expect(picker.browse.suggested == [.newYork])
        picker.searchText = "NY"
        #expect(picker.searchResults == .available([.newYork]))
        draft.toggle(.ontario)
        #expect(picker.browse.suggested == [.ontario, .newYork])
    }
}
