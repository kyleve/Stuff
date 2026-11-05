import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct RecordingHistoryViewTests {
    @Test func settingsInspectsAutomaticChoiceThenSavesAnExplicitOverrideAndReenters() async throws {
        let samples = try RecordingReviewTestSupport.strongMovementSamples()
        let fixture = try await RecordingReviewTestSupport.fixture(samples: samples)
        #expect(try await fixture.references().isEmpty)
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.showsLocationWelcome = false
        let session = WhereSession(
            services: fixture.services,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(86400) },
        )
        let root = MainTabs(session: session, initialDetails: nil, selectedYear: 2026)
            .environment(session)
            .environment(PreviewSupport.loadedModel())
            .environment(\.scenePhase, .active)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            let window = try #require(host.view.window)
            let rootController = try #require(window.rootViewController)
            try await waitForResolutionView("Main tabs ready") { findTabController(in: host) != nil
            }
            let tabs = try #require(findTabController(in: host))
            let settingsIndex = try #require(tabs.tabs.firstIndex {
                $0.title == String(localized: .tabSettings)
            })
            tabs.selectedIndex = settingsIndex
            if let selected = tabs.selectedViewController {
                tabs.delegate?.tabBarController?(tabs, didSelect: selected)
            }
            try await waitForResolutionView("Settings navigation ready") {
                tabs.selectedViewController
                    .flatMap { resolutionNavigationController(in: $0) } != nil
            }
            let navigation = try #require(tabs.selectedViewController.flatMap {
                resolutionNavigationController(in: $0)
            })
            @MainActor func tap(_ identifier: String, in view: UIView) async throws {
                try await revealResolutionElement(identifier, in: view)
                try await waitForResolutionView(identifier) {
                    resolutionEnabledElement(identifier, in: view) != nil
                }
                try activateResolutionElement(#require(resolutionEnabledElement(
                    identifier,
                    in: view,
                )))
            }
            try await tap("where_settings_group_recordingHistory", in: navigation.view)
            try await tap("where_recording_history_inspect", in: navigation.view)
            try await waitForResolutionView("Inspection presented") {
                resolutionPresentedController(in: rootController)?.view.window != nil
            }
            let inspection = try #require(resolutionPresentedController(in: rootController))
            let select = "where_recording_choose_\(RecordingReviewTestSupport.second.rawValue.uuidString)"
            try await revealResolutionElement(select, in: inspection.view)
            #expect(resolutionElement("where_recording_apply", in: inspection.view) == nil)
            #expect(try await fixture.controls().sourceChoices.isEmpty)
            try await tap(select, in: inspection.view)
            try await tap("where_recording_apply", in: inspection.view)
            try await waitForResolutionView("Saved confirmation at the top of the review") {
                try scrollResolutionList(in: inspection.view, toBottom: false)
                return resolutionElement("where_recording_saved", in: inspection.view) != nil
            }
            #expect(resolutionPresentedController(in: rootController) === inspection)
            let decision = try #require(try await fixture.controls().sourceChoices.first)
            #expect(decision.action == .select(RecordingReviewTestSupport.second))
            #expect(try decision.periods == [RecordingPeriod(
                start: RecordingReviewTestSupport.date(0),
                end: RecordingReviewTestSupport.date(86400),
            )])
            try await tap("where_recording_history_close", in: inspection.view)
            try await waitForResolutionView("Inspection closed") {
                resolutionPresentedController(in: rootController) == nil
            }
            _ = navigation.popViewController(animated: false)
            try await tap("where_settings_group_recordingHistory", in: navigation.view)
            try await tap("where_recording_history_inspect", in: navigation.view)
            try await waitForResolutionView("Inspection reentered") {
                resolutionPresentedController(in: rootController)?.view.window != nil
            }
            let reopened = try #require(resolutionPresentedController(in: rootController))
            try await revealResolutionElement(select, in: reopened.view)
            #expect(resolutionElement("where_recording_apply", in: reopened.view) == nil)
            try await tap("where_recording_history_close", in: reopened.view)
        }
        #expect(try await Set(fixture.store.allSamples()) == Set(samples))
        #expect(try await fixture.controls().sourceChoices.count == 1)
    }

    @Test func foundationSettingsDoNotOfferHistoryInspection() async throws {
        let root = SettingsView(report: PreviewSupport.loadedYearReportModel())
            .environment(PreviewSupport.loadedSession())
            .environment(PreviewSupport.loadedModel())
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Settings ready") {
                resolutionElement("where_settings_group_devices", in: host.view) != nil
            }
            #expect(resolutionElement("where_settings_group_recordingHistory", in: host.view) ==
                nil)
        }
    }
}
