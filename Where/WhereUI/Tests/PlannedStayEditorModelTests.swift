import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct PlannedStayEditorModelTests {
    @Test func newDraftRequiresDestinationAndStartsWithExactDates() throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let model = PlannedStayEditorModel(report: report, stay: nil, initialRegion: nil)

        #expect(!model.canSave)
        #expect(model.validationMessage != nil)
        #expect(!model.arrival.isFlexible)
        #expect(!model.departure.isFlexible)
        model.region = .newYork
        #expect(model.canSave)
        #expect(try model.draft.get().arrival.earliest == PlanningTestSupport.today)
    }

    @Test func flexibleArrivalMustFinishBeforeTheEarliestLastDay() throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let model = PlannedStayEditorModel(report: report, stay: nil, initialRegion: .newYork)
        model.arrival.isFlexible = true
        model.arrival.latest = PlanningTestSupport.today.adding(days: 3)
            .startOfDay(in: report.calendar)

        #expect(!model.canSave)
        #expect(model.validationMessage != nil)
        model.departure.earliest = model.arrival.latest
        #expect(model.canSave)
        let stay = try model.draft.get()
        #expect(stay.arrival.earliest == PlanningTestSupport.today)
        #expect(stay.arrival.latest == PlanningTestSupport.today.adding(days: 3))
        #expect(stay.shortestRange.lowerBound == stay.shortestRange.upperBound)
    }

    @Test func editingAStayRetainsItsIdentityAndOtherPlans() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let first = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today,
            through: PlanningTestSupport.today.adding(days: 7),
        )
        let second = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: 30),
            through: PlanningTestSupport.today.adding(days: 44),
        )
        try await report.forecasts.create(stay: first)
        try await report.forecasts.create(stay: second)
        let model = PlannedStayEditorModel(report: report, stay: first, initialRegion: nil)
        model.departure.earliest = PlanningTestSupport.today.adding(days: 10)
            .startOfDay(in: report.calendar)

        #expect(await model.save())
        let snapshot = try await report.services.plannedStays.snapshot()
        #expect(snapshot.stays.count == 2)
        #expect(snapshot.stays.first { $0.id == second.id } == second)
        #expect(snapshot.stays.first { $0.id == first.id }?.departure.latest == PlanningTestSupport
            .today.adding(days: 10))
    }

    @Test func savingAnUntrackedFutureDestinationDoesNotRequireLocationOrChangeTracking(
    ) async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let primary = [PrimaryRegion(region: .california, appearance: nil, order: 0)]
        try await report.services.setPrimaryRegions(primary)
        let model = PlannedStayEditorModel(report: report, stay: nil, initialRegion: .newYork)
        model.arrival.earliest = PlanningTestSupport.today.adding(days: 40)
            .startOfDay(in: report.calendar)
        model.departure.earliest = PlanningTestSupport.today.adding(days: 55)
            .startOfDay(in: report.calendar)

        #expect(await model.save())
        #expect(try await report.services.primaryRegions() == primary)
        let snapshot = try await report.services.plannedStays.snapshot()
        #expect(snapshot.stays.count == 1)
        #expect(snapshot.stays.first?.region == .newYork)
    }

    @Test func deletingOneStayPreservesTheOtherStayAndHome() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let first = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today,
            through: PlanningTestSupport.today.adding(days: 7),
        )
        let second = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: 30),
            through: PlanningTestSupport.today.adding(days: 44),
        )
        try await report.forecasts.create(stay: first)
        try await report.forecasts.create(stay: second)
        try await report.forecasts.setHomeRegion(.california)
        let model = PlannedStayEditorModel(report: report, stay: first, initialRegion: nil)

        #expect(await model.delete())
        let snapshot = try await report.services.plannedStays.snapshot()
        #expect(snapshot.stays == [second])
        #expect(snapshot.homeRegion == .california)
    }

    @Test func failedSaveKeepsTheDraftOpenAndObservable() async throws {
        let store = try TestStore()
        await store.failPlannedStays()
        let report = PlanningTestSupport.report(store: store)
        let model = PlannedStayEditorModel(report: report, stay: nil, initialRegion: .newYork)
        let draft = try model.draft.get()

        #expect(await model.save() == false)
        guard case .failed = model.saveState else {
            Issue.record("The save failure must stay visible in the editor")
            return
        }
        #expect(try model.draft.get() == draft)
        #expect(model.canSave)
        #expect(try await report.services.plannedStays.snapshot().stays.isEmpty)
    }

    @Test func overlapWarningsIncludeOtherPlansButNeverTheEditedRevisionItself() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: 1),
            through: PlanningTestSupport.today.adding(days: 7),
        )
        try await report.forecasts.create(stay: stay)
        await report.forecasts.refresh()
        let model = PlannedStayEditorModel(report: report, stay: stay, initialRegion: nil)
        #expect(model.overlaps.isEmpty)
        let other = try PlannedStay(
            id: PlannedStay.ID(rawValue: UUID()),
            region: .california,
            arrival: .init(
                earliest: PlanningTestSupport.today.adding(days: 5),
                latest: PlanningTestSupport.today.adding(days: 10),
            ),
            departure: .init(exact: PlanningTestSupport.today.adding(days: 14)),
        )
        try await report.forecasts.create(stay: other)
        await report.forecasts.refresh()
        #expect(model.hasPossibleOverlap)
        #expect(!model.hasDefiniteOverlap)
        #expect(model.canSave)
        model.departure.earliest = PlanningTestSupport.today.adding(days: 11)
            .startOfDay(in: report.calendar)
        #expect(model.hasDefiniteOverlap)
        #expect(model.canSave)
    }

    @Test(arguments: ["America/New_York", "America/Los_Angeles", "Pacific/Auckland"])
    func calendarDayBoundariesSurviveLocalDatePickerProjection(timeZoneID: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
        let window = try PlannedStay.DateWindow(
            earliest: CalendarDay(year: 2028, month: 2, day: 28),
            latest: CalendarDay(year: 2028, month: 3, day: 1),
        )
        let boundary = PlannedStayEditorModel.Boundary(window: window, calendar: calendar)
        #expect(try boundary.window(in: calendar) == window)
    }
}
