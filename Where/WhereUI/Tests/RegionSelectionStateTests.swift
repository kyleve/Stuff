import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The manual-day / relabel region toggles group into tracked / already-used /
/// everything-else once the tracked set loads, and membership stays stable as
/// rows are toggled.
struct RegionSelectionStateTests {
    private func region(_ id: String) throws -> Region {
        try #require(Region(rawValue: id))
    }

    private func primary(_ regions: [Region]) -> [PrimaryRegion] {
        regions.enumerated().map { PrimaryRegion(region: $1, appearance: nil, order: $0) }
    }

    @Test func flatUntilTrackedLoads() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, .newYork, texas, .other],
            selectedRegions: [.newYork],
        )
        // Before the tracked set loads, callers render the flat list.
        #expect(state.trackedRegions == nil)
        #expect(state.otherItems.map(\.region) == [.california, .newYork, texas, .other])
        #expect(state.trackedItems.isEmpty)
        #expect(state.usedItems.isEmpty)
    }

    @Test func partitionsIntoTrackedUsedAndEverythingElse() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, .newYork, texas, .other],
            selectedRegions: [.newYork, .other],
        )
        state.applyTracked(primary([.california, .newYork]))

        // Tracked first, in pick order.
        #expect(state.trackedItems.map(\.region) == [.california, .newYork])
        // Non-tracked but already on this day.
        #expect(state.usedItems.map(\.region) == [.other])
        // Everything else.
        #expect(state.otherItems.map(\.region) == [texas])
    }

    @Test func trackedTakesPrecedenceOverUsed() {
        let state = RegionSelectionState(
            regions: [.california, .newYork, .other],
            selectedRegions: [.california, .other],
        )
        state.applyTracked(primary([.california]))
        // California is tracked *and* initially selected → tracked, not used.
        #expect(state.trackedItems.map(\.region) == [.california])
        #expect(state.usedItems.map(\.region) == [.other])
    }

    @Test func togglingDoesNotChangeSectionMembership() throws {
        let texas = try region("us-TX")
        let state = RegionSelectionState(
            regions: [.california, texas, .other],
            selectedRegions: [],
        )
        state.applyTracked(primary([.california]))
        #expect(state.otherItems.map(\.region) == [texas, .other])

        // Turn on a row in "everything else" — it stays there, and the overall
        // selection reflects it.
        let texasItem = try #require(state.otherItems.first { $0.region == texas })
        texasItem.isOn = true
        #expect(state.otherItems.map(\.region) == [texas, .other])
        #expect(state.selectedRegions == [texas])
    }
}
