import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct HistoryNavigationModelTests {
    @Test func selectingAMonthRevealsTheFirstOverlappingStayWhenRowsArrive() {
        let model = HistoryNavigationModel()
        let month = CalendarDay(year: 2026, month: 3, day: 1)
        model.select(month: month, dateCalendar: HistoryNavigationTestSupport.calendar)
        model.timeline.restorePosition(in: 2026)
        model.timeline.reconcile(
            recordedItems: [],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        let stint = HistoryNavigationTestSupport.stint(
            from: month.adding(days: -2),
            through: month.adding(days: 4),
        )
        model.timeline.reconcile(
            recordedItems: [.stay(stint)],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.calendar.scrollPosition.viewID(type: CalendarDay.self) == month)
        #expect(model.timeline.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .recorded(stint.id))
        #expect(model.selection?.interval == month ... CalendarDay(year: 2026, month: 3, day: 31))
    }

    @Test func selectingAStayHighlightsItsIntervalAndRevealsItsFirstMonth() {
        let model = HistoryNavigationModel()
        let start = CalendarDay(year: 2026, month: 2, day: 27)
        let end = CalendarDay(year: 2026, month: 3, day: 5)
        let stint = HistoryNavigationTestSupport.stint(from: start, through: end)
        model.select(stint: stint, dateCalendar: HistoryNavigationTestSupport.calendar)
        #expect(model.selection?.interval == start ... end)
        #expect(model.selection?.region == .california)
        #expect(model.calendar.displayedMonth == CalendarDay(year: 2026, month: 2, day: 1))
        #expect(model.timeline.visibleItem == .recorded(stint.id))
        #expect(model.selectedInterval(in: 2025) == nil)
    }

    @Test func localScrollObservationsDoNotChangeSelectionOrMoveTheCompanionPane() {
        let model = HistoryNavigationModel()
        let selected = CalendarDay(year: 2026, month: 3, day: 1)
        let browsed = CalendarDay(year: 2026, month: 5, day: 1)
        model.select(month: selected, dateCalendar: HistoryNavigationTestSupport.calendar)
        let selection = model.selection
        model.calendar.recordVisibleMonths([browsed])
        #expect(model.selection == selection)
        #expect(model.calendar.scrollPosition.viewID(type: CalendarDay.self) == selected)
        #expect(model.timeline.visibleItem == nil)
        model.timeline.restorePosition(in: 2026)
        let stint = HistoryNavigationTestSupport.stint(
            from: browsed,
            through: browsed.adding(days: 8),
        )
        model.timeline.recordVisibleItems([.recorded(stint.id)], in: 2026)
        #expect(model.selection == selection)
        #expect(model.calendar.displayedMonth == browsed)
        #expect(model.calendar.scrollPosition.viewID(type: CalendarDay.self) == selected)
    }

    @Test func planningPresentationHasOneOwnerAcrossBothLenses() {
        let model = HistoryNavigationModel()
        model.calendar.planningDestination = .new(.california)
        #expect(model.planning.destination == .new(.california))
        model.planning.destination = nil
        #expect(model.calendar.planningDestination == nil)
    }
}
