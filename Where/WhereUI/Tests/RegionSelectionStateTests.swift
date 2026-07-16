import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The manual-day region toggles group into tracked / used-this-year /
/// everything-else once grouping loads; `.other` always stays in the last group,
/// and membership stays stable as rows are toggled.
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
        #expect(state.trackedRegions == nil)
        #expect(state.otherItems.map(\.region) == [.california, .newYork, texas, .other])
        #expect(state.trackedItems.isEmpty)
        #expect(state.usedItems.isEmpty)
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

        #expect(state.trackedItems.map(\.region) == [.california, .newYork])
        #expect(state.usedItems.map(\.region) == [texas])
        // FL (never used) and .other (always here) fall to everything-else.
        #expect(state.otherItems.map(\.region) == [florida, .other])
    }

    @Test func trackedTakesPrecedenceOverUsedThisYear() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, texas, .other],
            selectedRegions: [],
        )
        // California is tracked *and* used this year → tracked, not used.
        state.applyGrouping(tracked: primary([.california]), usedThisYear: [.california, texas])
        #expect(state.trackedItems.map(\.region) == [.california])
        #expect(state.usedItems.map(\.region) == [texas])
    }

    @Test func togglingDoesNotChangeSectionMembership() throws {
        let texas = try region("us-TX")
        let florida = try region("us-FL")
        let state = RegionSelectionState(
            regions: [.california, texas, florida, .other],
            selectedRegions: [],
        )
        state.applyGrouping(tracked: primary([.california]), usedThisYear: [texas])
        #expect(state.otherItems.map(\.region) == [florida, .other])

        // Turn on a row in everything-else — it stays there, and the overall
        // selection reflects it.
        let floridaItem = try #require(state.otherItems.first { $0.region == florida })
        floridaItem.isOn = true
        #expect(state.otherItems.map(\.region) == [florida, .other])
        #expect(state.selectedRegions == [florida])
    }
}
