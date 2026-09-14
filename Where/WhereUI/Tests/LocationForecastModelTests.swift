import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct LocationForecastModelTests {
    @Test func loadsExplicitDestinationsAndHomeWithoutChangingRecordedRanking() async throws {
        let store = try TestStore()
        let model = PlanningModelTestSupport.model(store: store)
        let stay = try PlanningModelTestSupport.stay(region: .newYork)
        try await model.create(stay: stay)
        try await model.setHomeRegion(.california)
        await model.refresh()
        let report = YearReport(year: 2026, days: [], totals: [:])

        #expect(Set(model.leadingForecasts(report: report).map(\.region)) == [
            .newYork,
            .california,
        ])
        #expect(RegionRanking(report: report).primary.isEmpty)
        #expect(model.loadFailure == nil)
    }

    @Test func writesWaitForTheSharedReadPathAndPreserveOtherTrips() async throws {
        let store = try TestStore()
        let model = PlanningModelTestSupport.model(store: store)
        await model.refresh()
        let first = try PlanningModelTestSupport.stay(region: .newYork)
        let second = try PlanningModelTestSupport.stay(region: .california)
        try await model.create(stay: first)
        try await model.create(stay: second)
        #expect(model.planning.stays.isEmpty)

        await model.refresh()
        #expect(Set(model.planning.stays.map(\.id)) == [first.id, second.id])
        try await model.delete(stayID: first.id)
        #expect(model.planning.stays.count == 2)
        await model.refresh()
        #expect(model.planning.stays == [second])
    }

    @Test func failedWritePreservesTheLoadedItinerary() async throws {
        let store = try TestStore()
        let model = PlanningModelTestSupport.model(store: store)
        let stay = try PlanningModelTestSupport.stay(region: .newYork)
        try await model.create(stay: stay)
        await model.refresh()
        await store.failPlannedStays()

        await #expect(throws: PlannedStaySaveFailure.self) {
            try await model.delete(stayID: stay.id)
        }
        #expect(model.planning.stays == [stay])
    }

    @Test func failedReadKeepsLastGoodValuesAndSurfacesFailure() async throws {
        let store = try TestStore()
        let model = PlanningModelTestSupport.model(store: store)
        let stay = try PlanningModelTestSupport.stay(region: .newYork)
        try await model.create(stay: stay)
        await model.refresh()
        await store.failPlanningReads()
        await model.refresh()

        #expect(model.hasLoaded)
        #expect(model.loadFailure != nil)
        #expect(model.planning.stays == [stay])
    }

    @Test func firstReadFailureDoesNotPublishAnEmptyForecastAsSuccess() async throws {
        let store = try TestStore()
        await store.failPlanningReads()
        let model = PlanningModelTestSupport.model(store: store)
        await model.refresh()

        #expect(!model.hasLoaded)
        #expect(model.loadFailure != nil)
        #expect(model.forecast(
            for: .newYork,
            report: YearReport(year: 2026, days: [], totals: [:]),
        ) == nil)
    }

    @Test func projectsOnlyTheFutureSliceAcrossYearBoundaries() async throws {
        let store = try TestStore()
        let model = PlanningModelTestSupport.model(store: store)
        let stay = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: .newYork,
            arrival: .init(exact: .init(year: 2026, month: 7, day: 15)),
            departure: .init(exact: .init(year: 2027, month: 1, day: 5)),
        )
        try await model.create(stay: stay)
        await model.refresh()

        #expect(model.plannedPresence(on: PlanningModelTestSupport.today).possibleRegions.isEmpty)
        #expect(model.plannedIntervals(intersecting: 2025).isEmpty)
        #expect(model.plannedIntervals(intersecting: 2026).first?.start == PlanningModelTestSupport
            .today.adding(days: 1))
        #expect(model.plannedIntervals(intersecting: 2027).first?.dayCount == DayBounds(exact: 5))
    }
}
