@_spi(Capture) import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct CalendarContentViewSnapshotTests {
    @Test func calendarContent() async {
        await assertSnapshots(of: MeasuredCalendarSnapshots.self)
    }

    @Test func retryAwaitsTheNewlyMountedCalendar() async throws {
        try waitFor { hostKeyWindow() != nil }
        var presentations: [CalendarPresentationState] = []
        func makeCalendar(_ presentation: CalendarPresentationState?) -> CalendarContentView {
            let presentation = presentation!
            presentations.append(presentation)
            return CalendarContentView(
                report: PreviewSupport.loadedYearReportModel(),
                presentationState: presentation,
            )
        }
        let snapshots = CalendarSnapshotCases(awaitsLayout: true).snapshot(
            name: "CalendarRetry",
            configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
            content: makeCalendar,
        )
        let snapshot = try #require(snapshots.first)
        guard case let .single(build) = snapshot.capture else {
            Issue.record("The retry probe requires a single calendar")
            return
        }
        // Match captureConfiguredSnapshot: build once, then rehost the same value.
        let content = build()
        var attempts = 0
        let image = try await SnapshotCaptureRetry.capture(
            named: "CalendarRetry",
            makeViewController: { UIHostingController(rootView: content) },
            capture: { controller in
                attempts += 1
                return try await renderSnapshotImage(
                    of: controller,
                    named: "CalendarRetry",
                    sizing: .intrinsic(width: 390, minimumHeight: 0),
                    safeAreaInsets: .zero,
                    measurementReadiness: .immediate,
                    onReadyToMeasure: {
                        await snapshot.onReadyToMeasure?()
                        #expect(presentations.count == attempts)
                        #expect(presentations.last?.year == PreviewSupport.year)
                        if attempts == 1 {
                            throw SnapshotRenderingError.settleTimedOut(
                                name: "CalendarRetry",
                                phase: "forced retry after readiness",
                                viewType: "CalendarContentView",
                                budget: 0,
                            )
                        }
                    },
                )
            },
            report: { _ in },
        )
        #expect(attempts == 2)
        #expect(presentations.count == 2)
        #expect(presentations.first !== presentations.last)
        #expect(image.size.height > 844)
    }

    private enum MeasuredCalendarSnapshots: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            CalendarContentView.measuredSnapshots
        }
    }
}
