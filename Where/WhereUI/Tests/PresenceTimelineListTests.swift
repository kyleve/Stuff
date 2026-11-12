import AccessibilitySnapshotParser
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct PresenceTimelineListTests {
    @Test func aPendingRevealRetriesWhenAStayExtendsWithoutChangingIdentity() async throws {
        let store = try TestStore()
        let report = PlanningTestSupport.report(store: store)
        for day in 20 ... 31 {
            try await report.services.journal.addManualDay(
                date: CalendarDay(year: report.selectedYear, month: 1, day: day)
                    .startOfDay(in: report.calendar),
                regions: [.california],
                audit: nil,
            )
        }
        await report.refresh()
        let before = try PresenceTimeline.stints(
            from: #require(report.report),
            calendar: report.calendar,
        )
        let original = try #require(before.first)
        let history = PresenceSelectionModel()
        history.select(
            month: CalendarDay(year: report.selectedYear, month: 2, day: 1),
            dateCalendar: report.calendar,
        )
        let host = UIHostingController(rootView: PresenceTimelineList(
            report: report,
            presentation: .linked,
            history: history,
        ).whereBroadwayRoot().bScrollRestorationScope())
        try await show(host) { _ in
            #expect(history.pendingRequest(for: .timeline) != nil)
            for day in 1 ... 3 {
                try await report.services.journal.addManualDay(
                    date: CalendarDay(year: report.selectedYear, month: 2, day: day)
                        .startOfDay(in: report.calendar),
                    regions: [.california],
                    audit: nil,
                )
            }
            await report.refresh()
            let updatedReport = try #require(report.report)
            let extended = try #require(PresenceTimeline.stints(
                from: updatedReport,
                calendar: report.calendar,
            ).first)
            #expect(extended.id == original.id)
            try await waitForAsync { history.pendingRequest(for: .timeline) == nil }
        }
    }

    @Test func selectingTheSameMonthAgainRevealsItAfterIndependentBrowsing() async throws {
        let world = try await WhereFlyoverWorld.build()
        let report = try #require(world.report.report)
        let history = PresenceSelectionModel()
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
        let expectedLabel = WhereFormat.timelineRowAccessibility(
            region: expected.region.localizedName,
            range: DateRangeFormatting
                .abbreviated(
                    start: expected.start,
                    end: expected.end,
                    calendar: world.report.calendar,
                ),
            days: expected.dayCount,
        )
        let browsedLabel = WhereFormat.timelineRowAccessibility(
            region: browsed.region.localizedName,
            range: DateRangeFormatting
                .abbreviated(
                    start: browsed.start,
                    end: browsed.end,
                    calendar: world.report.calendar,
                ),
            days: browsed.dayCount,
        )
        let capture = ScrollPositionCapture()
        let host = UIHostingController(rootView: PresenceTimelineList(
            report: world.report,
            presentation: .linked,
            history: history,
        ).overlay {
            ScrollPositionProbe(
                PresenceTimelineList.self,
                role: PresenceTimelineList.ScrollRole.timeline,
                context: report.year,
                idType: PresenceSelectionModel.Item.self,
                capture: capture,
            )
        }.whereBroadwayRoot().bScrollRestorationScope())

        try await show(host) { _ in
            for _ in 0 ..< 4 {
                history.select(month: month, dateCalendar: world.report.calendar)
                try await waitForAsync {
                    capture.binding?.wrappedValue
                        .viewID(type: PresenceSelectionModel.Item.self) == .recorded(expected.id)
                        && HostedAccessibility.isVisible(expectedLabel, in: host.view)
                }
                #expect(history.pendingRequest(for: .timeline) == nil)
                let selectedInterval = history.selection
                capture.binding?.wrappedValue.scrollTo(
                    id: PresenceSelectionModel.Item.recorded(browsed.id),
                    anchor: .top,
                )
                try await waitForAsync {
                    capture.binding?.wrappedValue
                        .viewID(type: PresenceSelectionModel.Item.self) == .recorded(browsed.id)
                        && HostedAccessibility.isVisible(browsedLabel, in: host.view)
                }
                #expect(capture.binding?.wrappedValue
                    .viewID(type: PresenceSelectionModel.Item.self) == .recorded(browsed.id))
                #expect(history.selection == selectedInterval)
            }
        }
    }
}
