import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct ResolutionViewTests {
    @Test func historicalReviewRemainsReachableAfterTheSelectedYearFails() async throws {
        let store = try TestStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 2)))
        let services = FlightReviewTestSupport.services(store: store, now: now)
        try await FlightReviewTestSupport.seed(into: store, includeArrival: false)
        let report = YearReportModel(
            services: services,
            selectedYear: 2027,
            preferences: makePreferences(),
            now: { now },
        )
        await report.refreshAll(forceDataIssueCount: true)
        let review = try #require(report.correctionReviews.first)
        let dateLabel = WhereFormat.calendarDay(
            review.day.day,
            format: .dateTime.month(.abbreviated).day().year(),
        )
        await store.failSamples()
        await report.select(year: 2028)
        guard case .failed = report.loadState else {
            Issue.record("Expected the selected-year report to fail")
            return
        }
        let root = LocationsView(report: report).whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            let window = try #require(host.view.window)
            let rootController = try #require(window.rootViewController)
            for _ in 0 ..< 2 {
                try await waitForResolutionView("Historical issues button") {
                    resolutionElement("where_resolution_button", in: window) != nil
                }
                try activateResolutionElement(#require(resolutionElement(
                    "where_resolution_button",
                    in: window,
                )))
                try await waitForResolutionView("Historical issue list") {
                    resolutionElement("where_resolution_list", in: window) != nil
                }
                let sheet = try #require(resolutionPresentedController(in: rootController))
                let navigation = try #require(resolutionNavigationController(in: sheet))
                @MainActor func historicalRow() -> NSObject? {
                    resolutionAccessibilityObjects(in: sheet.view).first {
                        $0.accessibilityLabel?.hasPrefix(dateLabel) == true
                            && $0.accessibilityTraits.contains(.button)
                    }
                }
                try await waitForResolutionView("Historical flight row") {
                    historicalRow()?.accessibilityTraits.contains(.notEnabled) == false
                }
                try activateResolutionElement(#require(historicalRow()))
                try await waitForResolutionView("Historical flight detail") {
                    navigation.viewControllers.count == 2 && navigation.transitionCoordinator == nil
                }
                // UIKit's synthetic Back accessibility element does not implement activation.
                // Pop the same live navigation stack and verify its production return lifecycle.
                try #require(navigation.popViewController(animated: true))
                try await waitForResolutionView("Return to historical issue list") {
                    navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil
                }
                let done = try #require(resolutionAccessibilityObjects(in: sheet.view).first {
                    $0.accessibilityLabel == String(localized: .commonDone)
                        && $0.accessibilityTraits.contains(.button)
                })
                try activateResolutionElement(done)
                try await waitForResolutionView("Close historical issue list") {
                    resolutionPresentedController(in: rootController) == nil
                }
            }
        }
    }
}
