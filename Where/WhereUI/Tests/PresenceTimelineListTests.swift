import AccessibilitySnapshotParser
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct PresenceTimelineListTests {
    @Test(arguments: [false, true])
    func estimateFollowsOnlyTheCurrentCardAndItsJoinedPlan(joins: Bool) throws {
        let today = PlanningModelTestSupport.today
        let calendar = PlanningModelTestSupport.calendar
        let current = RegionStint(
            region: .newYork,
            start: today.adding(days: -4).startOfDay(in: calendar),
            end: today.startOfDay(in: calendar),
            dayCount: 5,
        )
        let plan = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: joins ? .newYork : .california,
            arrival: .init(exact: today.adding(days: 1)),
            departure: .init(exact: today.adding(days: 5)),
        )
        let later = try PlannedStay(
            id: .init(rawValue: UUID()),
            region: .newYork,
            arrival: .init(exact: today.adding(days: 12)),
            departure: .init(exact: today.adding(days: 18)),
        )
        let planned = PlanningTimelineItem.items(
            planning: .init(stays: [later, plan], homeRegion: nil),
            year: today.year,
            today: today,
        )
        let items = PresenceTimelineRows.Item.ordered(
            recorded: [.stay(current)],
            planned: planned,
            estimateDay: today,
            calendar: calendar,
        )
        let currentRow = PresenceTimelineList.RowID.recorded(current.id)
        let firstPlan = PresenceTimelineList.RowID.planned(.stay(plan.id))
        let laterPlan = PresenceTimelineList.RowID.planned(.stay(later.id))
        #expect(items.map(\.id) == (joins
                ? [currentRow, firstPlan, .estimate, laterPlan]
                : [currentRow, .estimate, firstPlan, laterPlan]))
    }

    @Test func aRemountedTimelineRestoresItsBrowsedRowWithoutSelectionState() async throws {
        let model = PreviewSupport.itineraryYearReportModel()
        let report = try #require(model.report)
        let items = PresenceJourneyItem.items(
            stints: PresenceTimeline.stints(from: report, calendar: model.calendar),
            flights: model.completedFlights,
            year: report.year,
            calendar: model.calendar,
        )
        let stint = try #require(items.compactMap { item -> RegionStint? in
            if case let .stay(stint) = item { return stint }
            return nil
        }.first)
        let target = PresenceTimelineList.RowID.recorded(stint.id)
        let label = WhereFormat.timelineRowAccessibility(
            region: stint.region.localizedName,
            range: DateRangeFormatting.abbreviated(
                start: stint.start,
                end: stint.end,
                calendar: model.calendar,
            ),
            days: stint.dayCount,
        )
        let store = BScrollRestorationStore()
        let capture = ScrollPositionCapture()
        func timeline() -> some View {
            PresenceTimelineList(report: model)
                .overlay {
                    ScrollPositionProbe(
                        PresenceTimelineList.self,
                        role: PresenceTimelineList.ScrollRole.timeline,
                        context: report.year,
                        idType: PresenceTimelineList.RowID.self,
                        capture: capture,
                    )
                }
                .whereBroadwayRoot()
                .bScrollRestorationScope(store)
        }
        func waitForTimeline(
            _ stage: String,
            in view: UIView,
            until condition: () -> Bool,
        ) async throws {
            do {
                try await waitForAsync { condition() }
            } catch {
                let scrolls = AdaptivePaneTestSupport.descendants(
                    of: view,
                    matching: UIScrollView.self,
                )
                let geometry = scrolls.map {
                    "offset=\($0.contentOffset), size=\($0.contentSize), bounds=\($0.bounds), insets=\($0.adjustedContentInset)"
                }
                throw TestHostError(
                    "Timeline \(stage): \(error); target=\(String(describing: capture.binding?.wrappedValue.viewID(type: PresenceTimelineList.RowID.self))); \(geometry)",
                )
            }
        }
        let first = UIHostingController(rootView: timeline())
        try await show(first) { _ in
            try await waitForTimeline("initial estimate", in: first.view) {
                capture.binding?.wrappedValue
                    .viewID(type: PresenceTimelineList.RowID.self) == .estimate
                    && HostedAccessibility.isVisible(
                        String(localized: .locationForecastTitle),
                        in: first.view,
                    )
            }
            capture.binding?.wrappedValue.scrollTo(id: target, anchor: .top)
            try await waitForTimeline("browsed row", in: first.view) {
                HostedAccessibility.isVisible(
                    label,
                    in: first.view,
                )
            }
            #expect(capture.binding?.wrappedValue
                .viewID(type: PresenceTimelineList.RowID.self) == target)
            let row = try #require(HostedAccessibility.objects(in: first.view).first {
                $0.accessibilityLabel == label
            })
            #expect(row.accessibilityTraits.contains(.button) == false)
            #expect(row.accessibilityTraits.contains(.selected) == false)
        }
        let second = UIHostingController(rootView: timeline())
        try await show(second) { _ in
            try await waitForTimeline("restored row", in: second.view) {
                capture.binding?.wrappedValue
                    .viewID(type: PresenceTimelineList.RowID.self) == target
                    && HostedAccessibility.isVisible(label, in: second.view)
            }
        }
    }
}
