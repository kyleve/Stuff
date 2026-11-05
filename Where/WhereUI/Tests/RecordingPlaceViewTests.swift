import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct RecordingPlaceViewTests {
    @Test func settingsEntrySupportsLocationReviewStaleApplyAndReentry() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let original = try await RecordingPlaceTestSupport.save(fixture)
        let samples = try await fixture.store.allSamples()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.showsLocationWelcome = false
        let session = WhereSession(
            services: fixture.services,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(600) },
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
            let settingsIndex = try #require(tabs.tabs
                .firstIndex { $0.title == String(localized: .tabSettings) })
            tabs.selectedIndex = settingsIndex
            if let selected = tabs.selectedViewController {
                tabs.delegate?.tabBarController?(tabs, didSelect: selected)
            }
            try await waitForResolutionView("Settings navigation ready") {
                tabs.selectedViewController
                    .flatMap { resolutionNavigationController(in: $0) } != nil
            }
            let navigation = try #require(tabs.selectedViewController
                .flatMap { resolutionNavigationController(in: $0) })
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
            try await tap("where_settings_group_recordingPlaces", in: navigation.view)
            try await tap("where_recording_place_edit", in: navigation.view)
            try await waitForResolutionView("Place editor presented") {
                resolutionPresentedController(in: rootController)?.view.window != nil
            }
            let editor = try #require(resolutionPresentedController(in: rootController))
            try await tap("where_recording_place_choose_location", in: editor.view)
            try await waitForResolutionView("Location picker presented") {
                resolutionPresentedController(in: editor)?.view.window != nil
            }
            let picker = try #require(resolutionPresentedController(in: editor))
            try await revealResolutionElement("where_recording_place_latitude", in: picker.view)
            @MainActor func latitudeField(in view: UIView) -> UITextField? {
                if let field = view as? UITextField,
                   field.placeholder == String(localized: .recordingPlaceLatitude)
                {
                    return field
                }
                for child in view.subviews {
                    if let field = latitudeField(in: child) { return field }
                }
                return nil
            }
            try await waitForResolutionView("Native latitude field ready") {
                latitudeField(in: picker.view) != nil
            }
            let latitude = try #require(latitudeField(in: picker.view))
            #expect(latitude.becomeFirstResponder())
            latitude.selectedTextRange = latitude.textRange(
                from: latitude.beginningOfDocument,
                to: latitude.endOfDocument,
            )
            latitude.insertText("40.75")
            latitude.resignFirstResponder()
            try await tap("where_recording_place_use_location", in: picker.view)
            try await waitForResolutionView("Location selection returned") {
                resolutionPresentedController(in: editor) == nil
            }
            try await tap("where_recording_place_review", in: editor.view)
            try await waitForResolutionView("Place preview ready") {
                resolutionEnabledElement("where_recording_place_apply", in: editor.view) != nil
            }
            let late = try await fixture.services.recordingControlEdits.review(.place(
                placeID: original.placeID,
                validity: [.init(start: RecordingReviewTestSupport.date(600), end: nil)],
                action: .remove,
            ))
            #expect(try await fixture.services.recordingControlEdits.apply(late) == .applied)
            try await tap("where_recording_place_apply", in: editor.view)
            try await revealResolutionElement("where_recording_place_refreshed", in: editor.view)
            #expect(try await fixture.controls().places.count == 2)
            try await tap("where_recording_place_apply", in: editor.view)
            try await revealResolutionElement("where_recording_place_saved", in: editor.view)
            try await tap("where_recording_place_close", in: editor.view)
            try await waitForResolutionView("Place editor closed") {
                resolutionPresentedController(in: rootController) == nil
            }
            #expect(try await fixture.controls().places.count == 3)
            let history = try await fixture.services.recordingControlEdits.placeHistory()
            let segment = try #require(history.entries.first?.segments.first)
            guard case let .place(saved) = segment.resolution else {
                Issue.record("Expected saved place"); return
            }
            #expect(saved.coordinate.latitude == 40.75)
            #expect(saved.coordinate.longitude == -74)
            _ = navigation.popViewController(animated: false)
            try await tap("where_settings_group_recordingPlaces", in: navigation.view)
            try await tap("where_recording_place_edit", in: navigation.view)
            try await waitForResolutionView("Place editor reentered") {
                resolutionPresentedController(in: rootController)?.view.window != nil
            }
            let reopened = try #require(resolutionPresentedController(in: rootController))
            try await tap("where_recording_place_close", in: reopened.view)
        }
        #expect(try await fixture.store.allSamples() == samples)
    }

    @Test func foundationSettingsDoNotOfferPlaceControls() async throws {
        let session = PreviewSupport.loadedSession()
        let root = SettingsView(report: PreviewSupport.loadedYearReportModel())
            .environment(session)
            .environment(PreviewSupport.loadedModel())
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Settings ready") {
                resolutionElement("where_settings_group_devices", in: host.view) != nil
            }
            #expect(resolutionElement("where_settings_group_recordingPlaces", in: host.view) == nil)
        }
    }
}
