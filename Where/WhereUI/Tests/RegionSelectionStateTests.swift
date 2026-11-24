import Foundation
import RegionKit
import Testing
@testable import WhereCore
@testable import WhereUI

/// The manual-day region toggles group (via the shared `RegionGrouping`) into
/// tracked / used-this-year / everything-else once grouping loads, and expose
/// the toggle item for a grouped region.
struct RegionSelectionStateTests {
    @MainActor @Test func manualPickerLogsNunavutIndependentlyOfCanada() async throws {
        let state = RegionSelectionState()
        let nunavut = try region("ca-NU")
        let item = try #require(state.item(for: nunavut))
        item.isOn = true
        #expect(state.selectedRegions == [nunavut])
        #expect(state.item(for: .canada)?.isOn == false)
        #expect(state.item(for: .europeanUnion) != nil)
        #expect(state.item(for: .other) != nil)
        #expect(!state.items.contains { $0.region.rawValue == "united-states" })

        let session = PreviewSupport.loadedSession()
        let date = try #require(Calendar.current.date(from: DateComponents(
            year: 2028,
            month: 3,
            day: 15,
            hour: 12,
        )))
        try await session.services.journal.addManualDay(
            date: date,
            regions: state.selectedRegions,
            audit: nil,
        )
        let report = try await session.services.reports.yearReport(for: 2028)
        #expect(report.days.first { $0.regions.contains(nunavut) }?.regions == [nunavut])
    }

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
