import AccessibilitySnapshotParser
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct PresenceTimelineListTests {
    @Test func aRemountedTimelineRestoresItsBrowsedRowWithoutSelectionState() async throws {
        let world = try await WhereFlyoverWorld.build()
        let report = try #require(world.report.report)
        let items = PresenceJourneyItem.items(
            stints: PresenceTimeline.stints(from: report, calendar: world.report.calendar),
            flights: world.report.completedFlights,
            year: report.year,
            calendar: world.report.calendar,
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
                calendar: world.report.calendar,
            ),
            days: stint.dayCount,
        )
        let store = BScrollRestorationStore()
        let capture = ScrollPositionCapture()
        func timeline() -> some View {
            PresenceTimelineList(report: world.report)
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
            // Native scrolling can clear ScrollPosition.edge after reaching the bottom.
            // Wait for the rendered offset, not for the transient command to remain stored.
            try await waitForTimeline("initial bottom", in: first.view) {
                guard capture.binding != nil,
                      let scroll = AdaptivePaneTestSupport.descendants(
                          of: first.view,
                          matching: UIScrollView.self,
                      )
                      .first(where: { $0.contentSize.height > $0.bounds.height })
                else { return false }
                let bottom = scroll.contentSize.height - scroll.bounds.height + scroll
                    .adjustedContentInset.bottom
                return abs(scroll.contentOffset.y - bottom) < 1
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
