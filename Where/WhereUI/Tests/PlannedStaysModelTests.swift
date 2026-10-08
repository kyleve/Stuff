import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct PlannedStaysModelTests {
    @Test func completedStaysAreRetainedInTheCollapsedPastSection() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let completed = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: -10),
            through: PlanningTestSupport.today.adding(days: -1),
        )
        let current = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: -3),
            through: PlanningTestSupport.today,
        )
        try await report.forecasts.create(stay: completed)
        try await report.forecasts.create(stay: current)
        let model = PlannedStaysModel(report: report, initialRegion: nil)
        await model.load()

        #expect(model.upcoming == [current])
        #expect(model.past == [completed])
        #expect(!model.showsPast)
        model.edit(completed)
        #expect(model.editor?.stayID == completed.id)
        #expect(model.editor?.canSave == true)
    }

    @Test func historicalGapChoiceClearsHomeWithoutDeletingPlans() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today,
            through: PlanningTestSupport.today.adding(days: 7),
        )
        try await report.forecasts.create(stay: stay)
        try await report.forecasts.setHomeRegion(.california)
        let model = PlannedStaysModel(report: report, initialRegion: nil)
        await model.load()
        await model.usePastTravelPattern()

        let snapshot = try await report.services.plannedStays.snapshot()
        #expect(snapshot.homeRegion == nil)
        #expect(snapshot.stays == [stay])
    }

    @Test func addUsesTheShortcutRegionAndEachDraftHasItsOwnIdentity() throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let model = PlannedStaysModel(report: report, initialRegion: .newYork)
        model.add()
        let first = try #require(model.editor)
        #expect(first.region == .newYork)
        model.editor = nil
        model.add()
        let second = try #require(model.editor)
        #expect(second.stayID != first.stayID)
    }
}
