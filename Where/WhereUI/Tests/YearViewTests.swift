import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct YearViewTests {
    @Test func pagingRetainsScrollViewsAndSynchronizesSelection() async throws {
        let root = YearView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
        try await show(UIHostingController(rootView: root)) { host in
            host.view.window?.layer.speed = 1
            defer { YearViewTestSupport.attachScreenshot(of: host.view) }
            try await YearViewTestSupport.wait {
                YearViewTestSupport.visibleVerticalScrollView(in: host.view)?.contentOffset
                    .y ?? 0 > 100
            }
            let calendar = try #require(YearViewTestSupport
                .visibleVerticalScrollView(in: host.view))
            let pager = try #require(YearViewTestSupport.pager(in: host.view))
            #expect(YearViewTestSupport.trailingButtonCount(in: host.view) == 1)

            YearViewTestSupport.selectPage(1, in: pager)
            try await YearViewTestSupport.wait {
                YearViewTestSupport.visibleVerticalScrollView(in: host.view)
                    .map { $0 !== calendar } == true
                    && YearViewTestSupport.title(in: host.view) == YearMode.timeline.title
            }
            let timeline = try #require(YearViewTestSupport
                .visibleVerticalScrollView(in: host.view))
            timeline.setContentOffset(CGPoint(x: 0, y: 80), animated: false)

            for _ in 0 ..< 2 {
                YearViewTestSupport.selectPage(0, in: pager)
                try await YearViewTestSupport.wait {
                    YearViewTestSupport.visibleVerticalScrollView(in: host.view) === calendar
                        && YearViewTestSupport.title(in: host.view) == YearMode.calendar.title
                }
                YearViewTestSupport.selectPage(1, in: pager)
                try await YearViewTestSupport.wait {
                    YearViewTestSupport.visibleVerticalScrollView(in: host.view) === timeline
                        && abs(timeline.contentOffset.y - 80) < 1
                        && YearViewTestSupport.title(in: host.view) == YearMode.timeline.title
                }
            }
            #expect(YearViewTestSupport.title(in: host.view) == YearMode.timeline.title)
            #expect(YearViewTestSupport.trailingButtonCount(in: host.view) == 1)
        }
    }
}
