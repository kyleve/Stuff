import AccessibilitySnapshotParser
import SwiftUI
import Synchronization
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
@Suite(.serialized)
struct RecordingIgnoreViewTests {
    @Test func foundationDevicesDoNotOfferIgnoreControls() async throws {
        let session = PreviewSupport.loadedSession()
        let configurations = PreviewSupport.recordingDeviceConfigurations()
        let root = NavigationStack {
            DevicesSettingsView(session: session, configurations: configurations)
        }
        .environment(session)
        .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            for device in configurations {
                let rowID = "where_recording_ignore_device_" + device.id.rawValue.uuidString
                #expect(resolutionElement(rowID, in: host.view) == nil)
            }
        }
    }

    @Test func settingsTabRetainsTheIgnoreDestinationAndReloadsOnReturn() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.showsLocationWelcome = false
        let session = WhereSession(
            services: fixture.services,
            preferences: preferences,
            now: { RecordingReviewTestSupport.date(600) },
        )
        let rowID = "where_recording_ignore_device_" + RecordingReviewTestSupport.first.rawValue
            .uuidString
        let root = MainTabs(session: session, initialDetails: nil, selectedYear: 2026)
            .environment(session)
            .environment(PreviewSupport.loadedModel())
            .environment(\.scenePhase, .active)
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            try await waitForResolutionView("Main tabs ready") { findTabController(in: host) != nil
            }
            let tabs = try #require(findTabController(in: host))
            let settingsIndex = try #require(tabs.tabs
                .firstIndex { $0.title == String(localized: .tabSettings) })
            @MainActor func select(_ index: Int) {
                tabs.selectedIndex = index
                if let selected = tabs.selectedViewController {
                    tabs.delegate?.tabBarController?(tabs, didSelect: selected)
                }
            }
            select(settingsIndex)
            try await waitForResolutionView("Settings navigation ready") {
                tabs.selectedViewController
                    .flatMap { resolutionNavigationController(in: $0) } != nil
            }
            let navigation = try #require(tabs.selectedViewController
                .flatMap { resolutionNavigationController(in: $0) })
            try await revealResolutionElement("where_settings_group_devices", in: navigation.view)
            try activateResolutionElement(#require(resolutionEnabledElement(
                "where_settings_group_devices",
                in: navigation.view,
            )))
            try await revealResolutionElement(rowID, in: navigation.view)
            try activateResolutionElement(#require(resolutionEnabledElement(
                rowID,
                in: navigation.view,
            )))
            try await waitForResolutionView("Ignore history ready") {
                resolutionEnabledElement("where_recording_ignore_start", in: navigation.view) != nil
            }
            let history = try #require(navigation.topViewController)
            select(0)
            try await waitForResolutionView("Settings tab hidden") { history.view.window == nil }
            _ = try await RecordingIgnoreTestSupport.ignore(
                fixture: fixture,
                deviceID: RecordingReviewTestSupport.first,
                day: RecordingReviewTestSupport.day,
            )
            select(settingsIndex)
            try await waitForResolutionView("Retained ignore history reloads") {
                history.view.window != nil
                    && resolutionEnabledElement("where_recording_ignore_start", in: history.view) !=
                    nil
                    && resolutionElement("where_recording_ignore_decision", in: history.view) != nil
            }
            #expect(navigation.topViewController === history)
        }
    }

    @Test func devicesEntrySupportsReviewedIgnoreResumeUndoAndReentry() async throws {
        let fixture = try await RecordingReviewTestSupport.fixture()
        let clock = Mutex(RecordingReviewTestSupport.date(600))
        let session = WhereSession(
            services: fixture.services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            now: { clock.withLock { $0 } },
        )
        let initial = try await fixture.store.allSamples()
        let rowID = "where_recording_ignore_device_" + RecordingReviewTestSupport.first.rawValue
            .uuidString
        let root = NavigationStack { DevicesSettingsView(session: session) }
            .environment(session)
            .environment(\.scenePhase, .active)
            .environment(\.timeZone, .gmt)
            .whereBroadwayRoot()
        try await showResolution(UIHostingController(rootView: root)) { host in
            let window = try #require(host.view.window)
            let rootController = try #require(window.rootViewController)
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
            @MainActor func sheet() async throws -> UIViewController {
                try await waitForResolutionView("Ignore editor presented") {
                    resolutionPresentedController(in: rootController)?.view.window != nil
                }
                return try #require(resolutionPresentedController(in: rootController))
            }
            @MainActor func saveAndClose(_ editor: UIViewController) async throws {
                try await tap("where_recording_ignore_review", in: editor.view)
                try await tap("where_recording_ignore_apply", in: editor.view)
                try await revealResolutionElement("where_recording_ignore_saved", in: editor.view)
                try activateResolutionElement(#require(resolutionEnabledElement(
                    "where_recording_ignore_close",
                    in: editor.view,
                )))
                try await waitForResolutionView("Return to ignore history") {
                    resolutionPresentedController(in: rootController) == nil
                }
            }

            try await tap(rowID, in: host.view)
            let navigation = try #require(resolutionNavigationController(in: host))
            try await waitForResolutionView("Ignore history loaded") {
                resolutionEnabledElement("where_recording_ignore_start", in: navigation.view) != nil
            }
            let history = try #require(navigation.topViewController)
            try await tap("where_recording_ignore_start", in: history.view)
            let editor = try await sheet()
            try await tap("where_recording_ignore_review", in: editor.view)
            try await waitForResolutionView("Ignore preview ready") {
                resolutionEnabledElement("where_recording_ignore_apply", in: editor.view) != nil
            }
            let late = try RecordingReviewTestSupport.sample(
                deviceID: RecordingReviewTestSupport.second,
                seconds: 900,
            )
            try await fixture.add([late])
            try await tap("where_recording_ignore_apply", in: editor.view)
            try await revealResolutionElement("where_recording_ignore_refreshed", in: editor.view)
            #expect(try await fixture.controls().ignores.isEmpty)
            try await tap("where_recording_ignore_apply", in: editor.view)
            try await revealResolutionElement("where_recording_ignore_saved", in: editor.view)
            try activateResolutionElement(#require(resolutionEnabledElement(
                "where_recording_ignore_close",
                in: editor.view,
            )))
            try await waitForResolutionView("Ignore saved and editor dismissed") {
                resolutionPresentedController(in: rootController) == nil
            }
            clock.withLock { $0 = RecordingReviewTestSupport.date(1000) }
            try await tap("where_recording_ignore_resume", in: history.view)
            try await saveAndClose(sheet())
            let resumed = try await fixture.services.recordingControlEdits
                .ignoreHistory(for: RecordingReviewTestSupport.first)
            #expect(resumed.segments.map(\.resolution) == [.ignored, .eligible])
            #expect(resumed.segments.first?.period.end == RecordingReviewTestSupport.date(1000))
            try await tap("where_recording_ignore_undo", in: history.view)
            try await saveAndClose(sheet())
            let restored = try await fixture.services.recordingControlEdits
                .ignoreHistory(for: RecordingReviewTestSupport.first)
            #expect(restored.segments.allSatisfy { $0.resolution == .eligible })
            #expect(try await fixture.controls().ignores.count == 3)
            #expect(try await Set(fixture.store.allSamples()) == Set(initial + [late]))
            #expect(try await session.recordingDevices()
                .first { $0.id == RecordingReviewTestSupport.first }?
                .localAutomaticRecordingEnabled == true)

            navigation.popViewController(animated: false)
            try await waitForResolutionView("Devices screen returns") { resolutionVisibleElement(
                rowID,
                in: navigation.view,
            ) != nil }
            try await tap(rowID, in: navigation.view)
            try await waitForResolutionView("Saved ignore history can be reopened") {
                resolutionEnabledElement("where_recording_ignore_start", in: navigation.view) !=
                    nil && resolutionElement(
                        "where_recording_ignore_decision",
                        in: navigation.view,
                    ) != nil
            }
        }
    }
}
