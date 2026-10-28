import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The manual-day region toggles group (via the shared `RegionGrouping`) into
/// tracked / used-this-year / everything-else once grouping loads, and expose
/// the toggle item for a grouped region.
struct RegionSelectionStateTests {
    private func region(_ id: String) throws -> Region {
        try #require(Region(rawValue: id))
    }

    private func primary(_ regions: [Region]) -> [PrimaryRegion] {
        regions.enumerated().map { PrimaryRegion(region: $1, appearance: nil, order: $0) }
    }

    @Test func flatUntilGroupingLoads() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, .newYork, texas, .other],
            selectedRegions: [.newYork],
        )
        #expect(!state.isGrouped)
    }

    @Test func partitionsIntoTrackedUsedThisYearAndEverythingElse() throws {
        let texas = try region("us-TX")
        let florida = try region("us-FL")
        let state = RegionSelectionState(
            regions: [.california, .newYork, texas, florida, .other],
            selectedRegions: [],
        )
        // Used this year: TX (non-tracked) and .other — .other is excluded from
        // the used group by design.
        state.applyGrouping(
            tracked: primary([.california, .newYork]),
            usedThisYear: [texas, .other],
        )

        #expect(state.isGrouped)
        #expect(state.grouping.primary == [.california, .newYork])
        #expect(state.grouping.usedThisYear == [texas])
        // FL (never used) and .other (always here) fall to everything-else.
        #expect(state.grouping.other == [florida, .other])
    }

    @Test func exposesToggleItemForAGroupedRegion() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, texas],
            selectedRegions: [texas],
        )
        state.applyGrouping(tracked: primary([.california]), usedThisYear: [])
        #expect(state.item(for: texas)?.isOn == true)
        #expect(state.item(for: .california)?.isOn == false)
    }
}
