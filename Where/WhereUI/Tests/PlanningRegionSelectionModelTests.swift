import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct PlanningRegionSelectionModelTests {
    @Test func destinationSearchIncludesSupportedUntrackedRegions() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        try await report.services.setPrimaryRegions([
            PrimaryRegion(region: .california, appearance: nil, order: 0),
        ])
        let model = PlanningRegionSelectionModel(report: report)
        await model.load()
        #expect(model.trackedRegions == [.california])
        #expect(model.available == PrimaryRegionSelectionModel.usRegions)
        #expect(model.grouping.primary == [.california])
        #expect(model.grouping.other.contains(.newYork))
        model.searchText = "  New York \n"
        #expect(model.filteredRegions == [.newYork])
        #expect(try await report.services.primaryRegions().map(\.region) == [.california])
    }

    @Test func failedHomeSelectionRemainsVisibleAndCanBeRetried() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let model = PlanningRegionSelectionModel(report: report)
        let saved = await model.select(.newYork) { _ in throw PlannedStaySaveFailure() }
        #expect(!saved)
        guard case .failed = model.selectionState else {
            Issue.record("The region picker must keep the failed selection visible")
            return
        }
        let retried = await model.select(.newYork) { region in
            try await report.forecasts.setHomeRegion(region)
        }
        #expect(retried)
        #expect(model.selectionState == .idle)
        #expect(try await report.services.plannedStays.snapshot().homeRegion == .newYork)
    }
}
