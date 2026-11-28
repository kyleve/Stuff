import AccessibilitySnapshotParser
import PeriscopeCore
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct DiagnosticReportingSettingsModelTests {
    @Test func crashAndReplayChoicesStayPendingUntilRelaunch() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let effective = DiagnosticReportingConfiguration.defaults(isDebugBuild: false)
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: effective,
            applyRemoteLogging: { _, _ in },
        )

        model.sharesCrashReports = false
        model.sharesSessionReplays = true

        #expect(model.crashReportsPendingNextLaunch)
        #expect(model.sessionReplaysPendingNextLaunch)
        #expect(model.effectiveConfiguration.sharesCrashReports)
        #expect(model.effectiveConfiguration.sharesSessionReplays == false)
        #expect(preferences.diagnosticReportingConfiguration.sharesCrashReports == false)
        #expect(preferences.diagnosticReportingConfiguration.sharesSessionReplays)
    }

    @Test func remoteLoggingAppliesImmediately() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: .defaults(isDebugBuild: false),
            applyRemoteLogging: { _, _ in },
        )

        model.selectRemoteLevel(.notice)
        await waitUntil { model.applyState != .applying }

        #expect(model.applyState == .idle)
        #expect(model.effectiveRemoteLogging == .enabled(
            minimumLevel: .notice,
            exportPolicy: .init(mode: .baseline, enabledControls: []),
        ))
    }

    @Test func turningLoggingOffClearsFullMetadata() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.diagnosticReportingConfiguration = DiagnosticReportingConfiguration(
            sharesCrashReports: true,
            sharesSessionReplays: false,
            remoteLogging: .enabled(
                minimumLevel: .warning,
                exportPolicy: .init(
                    mode: .diagnostic,
                    enabledControls: RemoteLoggingConfiguration.personalDataControls,
                ),
            ),
        )
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: preferences.diagnosticReportingConfiguration,
            applyRemoteLogging: { _, _ in },
        )

        model.selectRemoteLevel(nil)
        await waitUntil { model.applyState != .applying }

        #expect(model.savedConfiguration.remoteLogging == .off)
        #expect(model.includesPersonalData == false)
    }

    #if DEBUG
        @Test(arguments: [
            LogExportControl.identifiers,
            .location,
            .userContent,
            .personalData,
        ])
        func partialPersonalDataGrantsKeepTheCombinedSwitchOn(control: LogExportControl) async {
            let custom = LogExportControl("example.custom")
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            preferences.diagnosticReportingConfiguration = .init(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .enabled(
                    minimumLevel: .warning,
                    exportPolicy: .init(mode: .diagnostic, enabledControls: [control, custom]),
                ),
            )
            let model = DiagnosticReportingSettingsModel(
                preferences: preferences,
                effectiveConfiguration: preferences.diagnosticReportingConfiguration,
                applyRemoteLogging: { _, _ in },
            )

            let confirmation = DiagnosticPersonalDataConfirmation(reporting: model)
            #expect(confirmation.includesPersonalData)
            confirmation.includesPersonalData = false
            await waitUntil { model.applyState != .applying }

            #expect(!confirmation.includesPersonalData)
            #expect(model.effectiveRemoteLogging.exportPolicy.enabledControls == [custom])
            #expect(preferences.diagnosticReportingConfiguration.remoteLogging.exportPolicy
                .enabledControls == [custom])
        }

        @Test func combinedPersonalDataSwitchPreservesConsumerControls() async {
            let custom = LogExportControl("example.custom")
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            preferences.diagnosticReportingConfiguration = .init(
                sharesCrashReports: false,
                sharesSessionReplays: false,
                remoteLogging: .enabled(
                    minimumLevel: .warning,
                    exportPolicy: .init(mode: .diagnostic, enabledControls: [custom]),
                ),
            )
            let model = DiagnosticReportingSettingsModel(
                preferences: preferences,
                effectiveConfiguration: preferences.diagnosticReportingConfiguration,
                applyRemoteLogging: { _, _ in },
            )
            #expect(model.includesPersonalData == false)
            model.enablePersonalData()
            #expect(model.includesPersonalData)
            #expect(model.savedConfiguration.remoteLogging.exportPolicy[custom])
            model.disablePersonalData()
            await waitUntil { model.applyState != .applying }
            #expect(model.includesPersonalData == false)
            #expect(model.effectiveRemoteLogging.exportPolicy.enabledControls == [custom])
            #expect(model.effectiveRemoteLogging.exportPolicy.mode == .diagnostic)
        }

        @Test func fullMetadataRequiresConfirmationAndAReopenedScreenStartsFresh() async throws {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            let model = DiagnosticReportingSettingsModel(
                preferences: preferences,
                effectiveConfiguration: .defaults(isDebugBuild: true),
                applyRemoteLogging: { _, _ in },
            )

            let first = DiagnosticPersonalDataConfirmation(reporting: model)
            first.includesPersonalData = true

            #expect(first.isPresented)
            #expect(model.includesPersonalData == false)

            let reopened = DiagnosticPersonalDataConfirmation(reporting: model)
            #expect(!reopened.isPresented)
            reopened.includesPersonalData = true
            let revision = try #require(reopened.pendingRevision)
            // SwiftUI may dismiss the dialog before it invokes the selected action.
            reopened.isPresented = false
            reopened.confirm(revision: revision)
            await waitUntil { model.applyState != .applying }

            #expect(!reopened.isPresented)
            #expect(model.includesPersonalData)
            #expect(preferences.diagnosticReportingConfiguration.remoteLogging.exportPolicy
                .enabledControls
                == RemoteLoggingConfiguration.personalDataControls)
        }

        @Test func aSupersededPolicyCannotUseAnEarlierConfirmation() throws {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            let model = DiagnosticReportingSettingsModel(
                preferences: preferences,
                effectiveConfiguration: .defaults(isDebugBuild: true),
                applyRemoteLogging: { _, _ in },
            )
            let originalLevel = try #require(model.selectedRemoteLevel)
            let confirmation = DiagnosticPersonalDataConfirmation(reporting: model)
            confirmation.includesPersonalData = true
            let revision = try #require(confirmation.pendingRevision)

            model.selectRemoteLevel(nil)
            model.selectRemoteLevel(originalLevel)
            #expect(!confirmation.isPresented)
            confirmation.confirm(revision: revision)
            #expect(!model.includesPersonalData)
        }

        @Test func leavingDiagnosticsDiscardsTheNativeConfirmation() async throws {
            let app = PreviewSupport.loadedModel()
            let reporting = app.diagnosticReporting
            reporting.selectRemoteLevel(.warning)
            reporting.disablePersonalData()
            let session = PreviewSupport.loadedSession()
            let item = PrivacyDiagnosticsSettingsView.Item.fullMetadata
            let result = try #require(PrivacyDiagnosticsSettingsView.searchResults.first {
                $0.focus == SettingsFocus(item)
            })
            let route = SettingsRoute(result)
            let navigation = SettingsView.Navigation()
            let root = SettingsView(
                report: PreviewSupport.loadedYearReportModel(),
                navigation: navigation,
                initialRoute: route,
            )
            .environment(app)
            .environment(session)
            .whereBroadwayRoot()
            let controller: UIViewController = UIHostingController(rootView: root)

            try await show(controller) { _ in
                let host = try #require(controller.view.window?.rootViewController)
                @MainActor func metadataToggle() -> NSObject? {
                    HostedAccessibility.objects(in: controller.view).first {
                        $0.accessibilityLabel == item.title
                    }
                }
                try await waitForAsync { metadataToggle() != nil }
                let control = try #require(metadataToggle())
                if let toggle = control as? UISwitch {
                    toggle.setOn(true, animated: false)
                    toggle.sendActions(for: .valueChanged)
                } else {
                    try #require(control.accessibilityActivate())
                }
                try await waitForAsync {
                    AdaptivePaneTestSupport.presentedController(from: host) != nil
                }
                let prompt = try #require(AdaptivePaneTestSupport.presentedController(from: host))
                #expect(!reporting.includesPersonalData)
                navigation.selectedRoute = SettingsRoute(.alerts)
                prompt.dismiss(animated: false)
                try await waitForAsync {
                    AdaptivePaneTestSupport.presentedController(from: host) == nil
                        && metadataToggle() == nil
                }
                navigation.selectedRoute = route
                try await waitForAsync { metadataToggle() != nil }
                #expect(AdaptivePaneTestSupport.presentedController(from: host) == nil)
                #expect(!reporting.includesPersonalData)
            }
        }
    #endif

    @Test func aSlowerOldChoiceCannotReplaceTheNewestChoice() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let gate = ApplyGate()
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: .defaults(isDebugBuild: false),
            applyRemoteLogging: { configuration, _ in
                await gate.apply(configuration)
            },
        )

        model.selectRemoteLevel(.info)
        await waitUntil { await gate.hasBlockedChoice }
        model.selectRemoteLevel(nil)
        await waitUntil { model.applyState != .applying }
        await gate.releaseBlockedChoice()
        await Task.yield()

        #expect(model.effectiveRemoteLogging == .off)
        #expect(model.applyState == .idle)
    }

    @Test func failedApplyKeepsTheLastEffectivePolicyAndCanRetry() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let attempts = ApplyAttempts()
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: .defaults(isDebugBuild: false),
            applyRemoteLogging: { configuration, _ in
                try await attempts.apply(configuration)
            },
        )

        model.selectRemoteLevel(.error)
        await waitUntil { model.applyState != .applying }

        guard case .failed = model.applyState else {
            Issue.record("Expected a failed remote logging apply")
            return
        }
        #expect(model.effectiveRemoteLogging == .off)

        model.retryRemoteLogging()
        await waitUntil { model.applyState != .applying }

        #expect(model.applyState == .idle)
        #expect(model.effectiveRemoteLogging.minimumLevel == .error)
    }

    @Test func runtimeFailureInvalidatesAnInFlightApply() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let gate = ApplyGate()
        let model = DiagnosticReportingSettingsModel(
            preferences: preferences,
            effectiveConfiguration: .defaults(isDebugBuild: false),
            applyRemoteLogging: { configuration, _ in
                await gate.apply(configuration)
            },
        )

        model.selectRemoteLevel(.info)
        await waitUntil { await gate.hasBlockedChoice }
        model.recordRuntimeFailure("provider failed")
        await gate.releaseBlockedChoice()
        await Task.yield()

        #expect(model.effectiveRemoteLogging == .off)
        #expect(model.applyState == .failed(message: "provider failed"))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async {
        for _ in 0 ..< 100 where await !condition() {
            await Task.yield()
        }
    }
}

private actor ApplyAttempts {
    enum Failure: Error { case firstAttempt }
    private var count = 0

    func apply(_: RemoteLoggingConfiguration) throws {
        count += 1
        if count == 1 {
            throw Failure.firstAttempt
        }
    }
}

private actor ApplyGate {
    private(set) var hasBlockedChoice = false
    private var continuation: CheckedContinuation<Void, Never>?

    func apply(_ configuration: RemoteLoggingConfiguration) async {
        guard configuration.minimumLevel == .info else { return }
        hasBlockedChoice = true
        await withCheckedContinuation { continuation = $0 }
    }

    func releaseBlockedChoice() {
        continuation?.resume()
        continuation = nil
    }
}
