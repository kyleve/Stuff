import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct HistoryCompletenessNoticeTests {
    @Test(arguments: [false, true])
    func reviewUsesIncompleteReportEvenWithAlertsOff(unassigned: Bool) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture(unresolved: unassigned)
        let resolved = try RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.first,
            seconds: 6 * 3600,
        )
        try await fixture.add([resolved])
        let originalSamples = try await fixture.store.allSamples()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.issueAlertsEnabled = false
        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2026,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        await report.refreshAll(forceDataIssueCount: true)
        let completeness = try #require(report.report?.completeness)
        #expect(!completeness.isComplete)
        #expect(completeness.affectedDays.count == (unassigned ? 0 : 1))
        #expect(completeness.hasUnassignedDays == unassigned)
        #expect(report.report?.totals[.california] == 1)

        let root = LocationsView(report: report)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Incomplete report exposes review") {
                resolutionElement("where_history_completeness_review", in: host.view) != nil
            }
            let labels = resolutionAccessibilityObjects(in: host.view)
                .compactMap(\.accessibilityLabel)
            if unassigned {
                #expect(labels.contains(String(localized: .historyIncompleteUnknownDates)))
            } else {
                #expect(labels
                    .contains(String(localized: .historyIncompleteDays(WhereFormat.dayCount(1)))))
            }
            try activateResolutionElement(#require(resolutionElement(
                "where_history_completeness_review",
                in: host.view,
            )))
            try await waitForResolutionView("Review flow remains reachable") {
                guard let presented = resolutionPresentedController(in: host) else { return false }
                return resolutionElement("where_recording_review_remaining", in: presented.view) !=
                    nil
            }
        }
        #expect(try await fixture.store.allSamples() == originalSamples)

        // Historical issues still exist, but cannot qualify an unaffected year's totals.
        await report.select(year: 2027)
        #expect(report.dataIssueCount > 0)
        #expect(report.report?.completeness.isComplete == true)
        try await showResolution(UIHostingController(rootView: root)) { host in
            host.view.layoutIfNeeded()
            #expect(resolutionElement("where_history_completeness_review", in: host.view) == nil)
        }
    }

    @Test func completingDisplayedYearKeepsHistoricalReviewPresented() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        try await fixture
            .add([RecordingReviewTestSupport.first, RecordingReviewTestSupport.second].map {
                try RecordingReviewTestSupport.sample(deviceID: $0, seconds: -43200)
            })
        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2026,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            now: { RecordingReviewTestSupport.date(86400) },
        )
        await report.refreshAll(forceDataIssueCount: true)
        let root = LocationsView(report: report).whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Incomplete review entry") {
                resolutionElement("where_history_completeness_review", in: host.view) != nil
            }
            try activateResolutionElement(#require(resolutionElement(
                "where_history_completeness_review",
                in: host.view,
            )))
            try await waitForResolutionView("Historical review presented") {
                guard let presented = resolutionPresentedController(in: host) else { return false }
                return resolutionElement("where_recording_review_remaining", in: presented.view) !=
                    nil
            }
            let presented = try #require(resolutionPresentedController(in: host))
            let choice = RecordingChoiceModel(services: fixture.services, periods: fixture.periods)
            await choice.load()
            await choice.choose(.select(RecordingReviewTestSupport.first))
            await choice.apply()
            #expect(choice.didApply)
            await report.refreshAll(forceDataIssueCount: true)
            #expect(report.report?.completeness.isComplete == true)
            #expect(report.dataIssueCount > 0)
            try await waitForResolutionView("Remaining historical work stays accessible") {
                resolutionPresentedController(in: host) === presented
                    && resolutionElement("where_recording_review_remaining", in: presented.view) !=
                    nil
                    && resolutionElement("where_history_completeness_review", in: host.view) == nil
            }
            #expect(resolutionElement("where_history_completeness_review", in: host.view) == nil)
            choice.deactivate()
        }
    }
}
