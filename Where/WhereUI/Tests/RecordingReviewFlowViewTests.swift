import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct RecordingReviewFlowViewTests {
    @Test func issueButtonSupportsSkipReentryScopeEditingAndStaleSave() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2027,
            preferences: makePreferences(),
            now: { RecordingReviewTestSupport.date(86400) },
        )
        await report.refreshAll(forceDataIssueCount: true)
        report.observeDataChanges()
        defer { report.deactivate() }
        let scan = try #require(report.resolutionState.scan)
        #expect(scan.recording.issues.count == 1)
        #expect(report.dataIssueCount == scan.issues.count + scan.recording.issues.count)
        let root = LocationsView(report: report).whereBroadwayRoot().environment(
            \.scenePhase,
            .active,
        )
        try await showResolution(UIHostingController(rootView: root)) { host in
            let window = try #require(host.view.window)
            let rootController = try #require(window.rootViewController)
            try await waitForResolutionView("Issues button") { resolutionElement(
                "where_resolution_button",
                in: window,
            ) != nil }
            try activateResolutionElement(#require(resolutionElement(
                "where_resolution_button",
                in: window,
            )))
            try await waitForResolutionView("Recording review entry") { resolutionElement(
                "where_recording_review_remaining",
                in: window,
            ) != nil }
            let issues = try #require(resolutionPresentedController(in: rootController))
            for pass in 0 ..< 2 {
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_review_remaining",
                    in: issues.view,
                )))
                try await waitForResolutionView("Recording review flow is ready") {
                    resolutionEnabledElement(
                        "where_recording_skip",
                        in: window,
                    ) != nil
                }
                let flow = try #require(resolutionPresentedController(in: rootController))
                if pass == 0 {
                    try activateResolutionElement(#require(resolutionElement(
                        "where_recording_skip",
                        in: flow.view,
                    )))
                    try await waitForResolutionView("Skipped work is retained") { resolutionElement(
                        "where_recording_resume",
                        in: flow.view,
                    ) != nil }
                    #expect(try await fixture.controls().sourceChoices.isEmpty)
                    try activateResolutionElement(#require(resolutionElement(
                        "where_recording_close",
                        in: flow.view,
                    )))
                    try await waitForResolutionView("Return to main issue list") {
                        resolutionPresentedController(in: rootController) === issues
                    }
                    continue
                }
                let choose = "where_recording_choose_\(RecordingReviewTestSupport.first.rawValue.uuidString)"
                try await waitForResolutionView("Source choice") { resolutionEnabledElement(
                    choose,
                    in: flow.view,
                ) != nil }
                try activateResolutionElement(#require(resolutionElement(choose, in: flow.view)))
                try await waitForResolutionView("Scope editing") { resolutionEnabledElement(
                    "where_recording_edit_scope",
                    in: flow.view,
                ) != nil }
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_edit_scope",
                    in: flow.view,
                )))
                try await waitForResolutionView("Scope editor") { resolutionElement(
                    "where_recording_scope_review",
                    in: window,
                ) != nil }
                let editor = try #require(resolutionPresentedController(in: rootController))
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_scope_review",
                    in: editor.view,
                )))
                try await waitForResolutionView("Scope preview returns") {
                    resolutionPresentedController(in: rootController) === flow &&
                        resolutionEnabledElement(
                            "where_recording_edit_scope",
                            in: flow.view,
                        ) != nil
                }
                try await fixture.add([RecordingReviewTestSupport.sample(
                    deviceID: RecordingReviewTestSupport.second,
                    seconds: 900,
                )])
                try await waitForResolutionView("Apply choice") {
                    try scrollResolutionList(in: flow.view, toBottom: true)
                    return resolutionEnabledElement("where_recording_apply", in: flow.view) != nil
                }
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_apply",
                    in: flow.view,
                )))
                try await waitForResolutionView("Changed inputs require another review") {
                    try scrollResolutionList(in: flow.view, toBottom: false)
                    return resolutionElement(
                        "where_recording_refreshed",
                        in: flow.view,
                    ) != nil
                }
                #expect(try await fixture.controls().sourceChoices.isEmpty)
                try await waitForResolutionView("Apply refreshed proposal") {
                    try scrollResolutionList(in: flow.view, toBottom: true)
                    return resolutionEnabledElement("where_recording_apply", in: flow.view) != nil
                }
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_apply",
                    in: flow.view,
                )))
                try await waitForResolutionView("Complete only after reassessment") {
                    resolutionElement(
                        "where_recording_complete",
                        in: flow.view,
                    ) != nil
                }
                #expect(try await fixture.controls().sourceChoices.count == 1)
                #expect(try await fixture.controls().sourceChoices.first?.periods == fixture
                    .periods)
                try activateResolutionElement(#require(resolutionElement(
                    "where_recording_close",
                    in: flow.view,
                )))
                try await waitForResolutionView("Return after saved choice") {
                    resolutionPresentedController(in: rootController) === issues
                }
                try await waitForResolutionView("Shared historical scan removes resolved work") {
                    report.resolutionState.scan?.recording.issues.isEmpty == true
                }
                try await waitForResolutionView(
                    "Main list no longer shows resolved recording work",
                ) {
                    resolutionVisibleElement("where_recording_review_remaining", in: issues.view) ==
                        nil
                }
            }
        }
    }
}
