import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct TimelineNavigationModelTests {
    @Test func selectionBeforeTheFirstMountTakesPriorityOverTheInitialAnchor() {
        let model = TimelineNavigationModel()
        let day = CalendarDay(year: 2026, month: 2, day: 1)
        let selected = HistoryNavigationTestSupport.stint(from: day, through: day.adding(days: 3))
        let current = HistoryNavigationTestSupport.stint(
            from: day.adding(days: 30),
            through: day.adding(days: 40),
        )
        model.reveal(.recorded(selected.id))
        model.restorePosition(in: 2026, initialItem: .recorded(current.id))
        #expect(model.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .recorded(selected.id))
    }

    @Test func linkedTimelineStartsAtCurrentHistoryAndThenRestoresBrowsing() {
        let model = TimelineNavigationModel()
        let day = CalendarDay(year: 2026, month: 7, day: 10)
        let current = HistoryNavigationTestSupport.stint(from: day, through: day.adding(days: 3))
        let earlier = HistoryNavigationTestSupport.stint(
            from: day.adding(days: -20),
            through: day.adding(days: -10),
        )
        model.restorePosition(in: 2026, initialItem: .recorded(current.id))
        #expect(model.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .recorded(current.id))
        model.recordVisibleItems([.recorded(earlier.id)], in: 2026)
        model.restorePosition(in: 2026, initialItem: .recorded(current.id))
        #expect(model.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .recorded(earlier.id))
    }

    @Test func remountRestoresTheLocalAnchorWithoutACompanionCommand() {
        let model = TimelineNavigationModel()
        let day = CalendarDay(year: 2026, month: 4, day: 1)
        let stint = HistoryNavigationTestSupport.stint(from: day, through: day.adding(days: 8))
        model.restorePosition(in: 2026)
        model.recordVisibleItems([.recorded(stint.id)], in: 2026)
        model.restorePosition(in: 2026)
        #expect(model.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .recorded(stint.id))
    }

    @Test func aNewYearDiscardsAnOlderPendingMonthAndVisibilityCallback() {
        let model = TimelineNavigationModel()
        let month = CalendarDay(year: 2025, month: 12, day: 1)
        let stint = HistoryNavigationTestSupport.stint(from: month, through: month.adding(days: 8))
        model.restorePosition(in: 2025)
        model.reveal(month: month)
        model.restorePosition(in: 2026)
        model.recordVisibleItems([.recorded(stint.id)], in: 2025)
        model.reconcile(
            recordedItems: [.stay(stint)],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.visibleItem == nil)
        #expect(model.scrollPosition.viewID(type: TimelineNavigationModel.Item.self) == nil)
    }

    @Test func monthSelectionCanResolveAgainstAStayWhoseEndChanges() {
        let model = TimelineNavigationModel()
        let january = CalendarDay(year: 2026, month: 1, day: 20)
        let february = CalendarDay(year: 2026, month: 2, day: 1)
        model.restorePosition(in: 2026)
        model.reveal(month: february)
        let short = HistoryNavigationTestSupport.stint(
            from: january,
            through: january.adding(days: 1),
        )
        model.reconcile(
            recordedItems: [.stay(short)],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.visibleItem == nil)
        let extended = HistoryNavigationTestSupport.stint(
            from: january,
            through: february.adding(days: 2),
        )
        #expect(short.id == extended.id)
        model.reconcile(
            recordedItems: [.stay(extended)],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.visibleItem == .recorded(extended.id))
    }

    @Test func monthSelectionRevealsTheDisplayedSegmentAfterAFlight() throws {
        let model = TimelineNavigationModel()
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
            calendar: HistoryNavigationTestSupport.calendar,
        )
        let displayed = try #require(items.last)
        #expect(TimelineNavigationModel.Item(displayed) != .recorded(stint.id))
        model.restorePosition(in: 2026)
        model.reveal(month: february)
        model.reconcile(
            recordedItems: items,
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.visibleItem == TimelineNavigationModel.Item(displayed))
        #expect(model.requestedMonth == nil)
    }

    @Test func flightOnlyHistoryResolvesACrossMonthFlightAndRestoresItsAnchor() {
        let model = TimelineNavigationModel()
        let february = CalendarDay(year: 2026, month: 2, day: 1)
        let flight = HistoryNavigationTestSupport.flight(
            from: february.adding(days: -1),
            through: february,
        )
        model.restorePosition(in: 2026)
        model.reveal(month: february)
        model.reconcile(
            recordedItems: [.flight(flight)],
            plannedItems: [],
            calendar: HistoryNavigationTestSupport.calendar,
        )
        #expect(model.visibleItem == .flight(flight.id))
        model.restorePosition(in: 2026)
        #expect(model.scrollPosition
            .viewID(type: TimelineNavigationModel.Item.self) == .flight(flight.id))
    }
}
