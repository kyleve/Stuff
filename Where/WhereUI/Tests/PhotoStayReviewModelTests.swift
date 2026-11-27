import RegionKit
import Testing
@testable import WhereUI

@MainActor
struct PhotoStayReviewModelTests {
    @Test func recommendationsPreserveExplicitPicks() {
        let selection = PrimaryRegionSelectionModel(available: [.california, .newYork])
        selection.suggestRegions(from: [.newYork: 2, .california: 1, .other: 9])
        #expect(selection.suggestedRegions == [.newYork, .california])
        #expect(selection.selectedRegions.isEmpty)
        selection.toggle(.california)
        selection.suggestRegions(from: [.newYork: 3])
        #expect(selection.selectedRegions == [.california])
        selection.suggestRegions(from: [.california: 2, .newYork: 2])
        #expect(selection.suggestedRegions == [.california, .newYork])
    }
}
