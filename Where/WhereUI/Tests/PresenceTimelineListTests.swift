import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct PresenceTimelineListTests {
    @Test func selectingTheSameMonthAgainRevealsItAfterIndependentBrowsing() async throws {
        let world = try await WhereFlyoverWorld.build()
        let report = try #require(world.report.report)
        let history = HistoryNavigationModel()
        let month = CalendarDay(year: report.year, month: 5, day: 1)
        let end = CalendarDay(year: report.year, month: 5, day: 31)
        let stints = PresenceTimeline.stints(from: report, calendar: world.report.calendar)
        let items = PresenceJourneyItem.items(
            stints: stints,
            flights: world.report.completedFlights,
            year: report.year,
            calendar: world.report.calendar,
        )
        let displayedStints = items.compactMap { item -> RegionStint? in
            if case let .stay(stint) = item { return stint }
            return nil
        }
        let expected = try #require(displayedStints.first {
            CalendarDay(from: $0.start, in: world.report.calendar) <= end
                && CalendarDay(from: $0.end, in: world.report.calendar) >= month
        })
        let browsed = try #require(displayedStints.last)
        #expect(expected.id != browsed.id)
        let host = UIHostingController(rootView: PresenceTimelineList(
            report: world.report,
            presentation: .linked,
            history: history,
        ).whereBroadwayRoot())

        try await show(host) { _ in
            for _ in 0 ..< 4 {
                history.select(month: month, dateCalendar: world.report.calendar)
                try await waitForAsync { history.timeline.visibleItem == .recorded(expected.id) }
                #expect(history.timeline.requestedMonth == nil)
                let selectedInterval = history.selection
                history.timeline.recordVisibleItems([.recorded(browsed.id)], in: report.year)
                #expect(history.timeline.visibleItem == .recorded(browsed.id))
                #expect(history.selection == selectedInterval)
            }
        }
    }
}
