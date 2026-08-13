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
            metadataPolicy: .approvedFields,
        ))
    }

    @Test func turningLoggingOffClearsFullMetadata() async {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.diagnosticReportingConfiguration = DiagnosticReportingConfiguration(
            sharesCrashReports: true,
            sharesSessionReplays: false,
            remoteLogging: .enabled(
                minimumLevel: .warning,
                metadataPolicy: .allMetadataExcludingAttachmentData,
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
        #expect(model.includesAllLogMetadata == false)
    }

    #if DEBUG
        @Test func fullMetadataRequiresConfirmationAndPersistsItsWarningState() async {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            let model = DiagnosticReportingSettingsModel(
                preferences: preferences,
                effectiveConfiguration: .defaults(isDebugBuild: true),
                applyRemoteLogging: { _, _ in },
            )

            model.includeAllMetadataToggle = true

            #expect(model.isMetadataConfirmationPresented)
            #expect(model.includesAllLogMetadata == false)

            model.confirmAllLogMetadata()
            await waitUntil { model.applyState != .applying }

            #expect(model.isMetadataConfirmationPresented == false)
            #expect(model.includesAllLogMetadata)
            #expect(preferences.diagnosticReportingConfiguration.remoteLogging.metadataPolicy
                == .allMetadataExcludingAttachmentData)
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
        if count == 1 { throw Failure.firstAttempt }
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
