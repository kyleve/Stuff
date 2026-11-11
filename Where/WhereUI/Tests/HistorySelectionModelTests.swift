import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct HistorySelectionModelTests {
    private let calendar = HistoryNavigationTestSupport.calendar

    @Test func eachPaneConsumesItsRequestIndependentlyAndRepeatedSelectionGetsANewID() throws {
        let model = HistorySelectionModel()
        let month = CalendarDay(year: 2026, month: 3, day: 1)
        model.select(month: month, dateCalendar: calendar)
        let first = try #require(model.pendingRequest(for: .calendar))
        model.consume(first.id, by: .calendar)
        #expect(model.requestID == first.id)
        #expect(model.pendingRequest(for: .calendar) == nil)
        #expect(model.pendingRequest(for: .timeline)?.id == first.id)
        model.select(month: month, dateCalendar: calendar)
        let second = try #require(model.pendingRequest(for: .calendar))
        #expect(second.id != first.id)
        model.consume(first.id, by: .calendar)
        #expect(model.pendingRequest(for: .calendar)?.id == second.id)
        #expect(model.selection?.interval == month ... CalendarDay(year: 2026, month: 3, day: 31))
        model.reset()
        #expect(model.selection == nil)
        #expect(model.requestID == nil)
    }

    @Test func aPendingMonthResolvesWhenAnOverlappingStayArrivesOrExtends() {
        let model = HistorySelectionModel()
        let january = CalendarDay(year: 2026, month: 1, day: 20)
        let february = CalendarDay(year: 2026, month: 2, day: 1)
        model.select(month: february, dateCalendar: calendar)
        let short = HistoryNavigationTestSupport.stint(
            from: january,
            through: january.adding(days: 1),
        )
        #expect(model
            .timelineTarget(recordedItems: [], plannedItems: [], calendar: calendar) == nil)
        #expect(model.timelineTarget(
            recordedItems: [.stay(short)],
            plannedItems: [],
            calendar: calendar,
        ) == nil)
        let extended = HistoryNavigationTestSupport.stint(
            from: january,
            through: february.adding(days: 2),
        )
        #expect(short.id == extended.id)
        #expect(model.timelineTarget(
            recordedItems: [.stay(extended)],
            plannedItems: [],
            calendar: calendar,
        ) == .recorded(extended.id))
        #expect(model.pendingRequest(for: .timeline) != nil)
    }

    @Test func resolvesDisplayedSegmentsAndCrossMonthFlights() throws {
        let model = HistorySelectionModel()
        let january = CalendarDay(year: 2026, month: 1, day: 1)
        let february = CalendarDay(year: 2026, month: 2, day: 1)
        let stint = HistoryNavigationTestSupport.stint(
            from: january,
            through: february.adding(days: 9),
        )
        let flight = HistoryNavigationTestSupport.flight(
            from: february.adding(days: -1),
            through: february.adding(days: -1),
        )
        let items = PresenceJourneyItem.items(
            stints: [stint],
            flights: [flight],
            year: 2026,
            calendar: calendar,
        )
        let displayed = try #require(items.last)
        model.select(month: february, dateCalendar: calendar)
        #expect(HistorySelectionModel.Item(displayed) != .recorded(stint.id))
        #expect(model
            .timelineTarget(recordedItems: items, plannedItems: [], calendar: calendar) ==
            HistorySelectionModel.Item(displayed))
        let crossing = HistoryNavigationTestSupport.flight(
            from: february.adding(days: -1),
            through: february,
        )
        #expect(model.timelineTarget(
            recordedItems: [.flight(crossing)],
            plannedItems: [],
            calendar: calendar,
        ) == .flight(crossing.id))
    }

    @Test func explicitStaySelectionRetainsTypedIdentityAndInterval() {
        let model = HistorySelectionModel()
        let start = CalendarDay(year: 2026, month: 2, day: 27)
        let end = CalendarDay(year: 2026, month: 3, day: 5)
        let stint = HistoryNavigationTestSupport.stint(from: start, through: end)
        model.select(stint: stint, dateCalendar: calendar)
        #expect(model.selection?.interval == start ... end)
        #expect(model.selection?.region == .california)
        #expect(model.pendingRequest(for: .calendar)?.month == CalendarDay(
            year: 2026,
            month: 2,
            day: 1,
        ))
        #expect(model.timelineTarget(
            recordedItems: [.stay(stint)],
            plannedItems: [],
            calendar: calendar,
        ) == .recorded(stint.id))
        #expect(model.selectedInterval(in: 2025) == nil)
    }
}
