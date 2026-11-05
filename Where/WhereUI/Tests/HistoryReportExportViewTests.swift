import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct HistoryReportExportViewTests {
    @Test func systemPickerCancellationRetiresTheDocumentAndAllowsAnotherAttempt() async throws {
        let fixture = try await HistoryReportExportTestSupport.completeFixture()
        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2026,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            now: { RecordingReviewTestSupport.date(86400) },
        )
        let model = HistoryReportExportTestSupport.model(fixture, year: 2026)
        let root = NavigationStack { HistoryReportExportView(report: report, model: model) }
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            @MainActor func picker(in controller: UIViewController)
                -> UIDocumentPickerViewController?
            {
                if let picker = controller as? UIDocumentPickerViewController { return picker }
                if let presented = controller.presentedViewController,
                   let picker = picker(in: presented) { return picker }
                return controller.children.lazy.compactMap { picker(in: $0) }.first
            }
            for _ in 0 ..< 2 {
                try await revealResolutionElement("where_history_export_prepare", in: host.view)
                try activateResolutionElement(#require(resolutionEnabledElement(
                    "where_history_export_prepare",
                    in: host.view,
                )))
                try await waitForResolutionView("System file picker is presented") {
                    picker(in: host)?.view.window != nil
                }
                let presented = try #require(picker(in: host))
                let export = try #require(model.state.export)
                let delegate = try #require(presented.delegate)
                // Exercise SwiftUI's real UIKit delegate bridge, including the dismissal
                // UIKit performs when cancelling. This does not exercise the Cancel hit target.
                delegate.documentPickerWasCancelled?(presented)
                if presented.presentingViewController != nil {
                    await withCheckedContinuation { continuation in
                        presented.dismiss(animated: false) { continuation.resume() }
                    }
                }
                try await waitForResolutionView("Cancellation restores the export action") {
                    model.canExport && !model.isPresentingExporter && picker(in: host) == nil
                }
                #expect(throws: HistoryReportDocument.ExportError.retired) {
                    try export.document.exportedData()
                }
            }
        }
    }

    @Test func settingsExportRoutesUnresolvedHistoryToReviewAndReturnsWithoutExporting(
    ) async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let samples = try await fixture.store.allSamples()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let session = WhereSession(
            services: fixture.services,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2026,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        await report.refreshAll(forceDataIssueCount: true)
        let root = SettingsView(report: report)
            .environment(session)
            .environment(PreviewSupport.loadedModel())
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Settings navigation ready") {
                resolutionNavigationController(in: host) != nil
            }
            let navigation = try #require(resolutionNavigationController(in: host))
            @MainActor func tap(_ identifier: String, in view: UIView) async throws {
                try await revealResolutionElement(identifier, in: view)
                try await waitForResolutionView(identifier) { resolutionEnabledElement(
                    identifier,
                    in: view,
                ) != nil }
                try activateResolutionElement(#require(resolutionEnabledElement(
                    identifier,
                    in: view,
                )))
            }
            try await tap("where_settings_group_data", in: navigation.view)
            try await tap("where_settings_export_history", in: navigation.view)
            try await tap("where_history_export_prepare", in: navigation.view)
            try await waitForResolutionView("Incomplete export exposes review") {
                resolutionElement("where_history_completeness_review", in: navigation.view) != nil
            }
            #expect(resolutionPresentedController(in: host) == nil)
            try await tap("where_history_completeness_review", in: navigation.view)
            try await waitForResolutionView("Historical review presented") {
                guard let review = resolutionPresentedController(in: host) else { return false }
                return resolutionElement("where_recording_review_remaining", in: review.view) != nil
            }
            let review = try #require(resolutionPresentedController(in: host))
            let done = try #require(resolutionAccessibilityObjects(in: review.view).first {
                $0.accessibilityLabel == String(localized: .commonDone) && $0.accessibilityTraits
                    .contains(.button)
            })
            try activateResolutionElement(done)
            try await waitForResolutionView("Review closes without a system exporter") {
                resolutionPresentedController(in: host) == nil
            }
            #expect(resolutionEnabledElement("where_history_export_prepare", in: navigation.view) !=
                nil)
            try await tap("where_history_export_prepare", in: navigation.view)
            try await waitForResolutionView("A new assessment still requires review") {
                resolutionEnabledElement(
                    "where_history_completeness_review",
                    in: navigation.view,
                ) !=
                    nil
            }
            #expect(resolutionPresentedController(in: host) == nil)
            _ = navigation.popViewController(animated: false)
            try await tap("where_settings_export_history", in: navigation.view)
            #expect(resolutionElement("where_history_completeness_review", in: navigation.view) ==
                nil)
        }
        #expect(try await fixture.store.allSamples() == samples)
        #expect(try await fixture.controls().sourceChoices.isEmpty)
    }
}
