import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct WherePreferencesTests {
    private func preferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    @Test func firstInstallDefaults() {
        let preferences = preferences()

        #expect(preferences.hasOnboarded == false)
        #expect(preferences.showsRecordedLocationDots)
        #expect(preferences.showsLocationWelcome)
        #expect(preferences.theme == .standard)
        #expect(preferences.showsEstimatedTimeAndPlanning)
        #expect(preferences.remindersEnabled)
        #expect(preferences.reminderTime == .defaultEvening)
        #expect(preferences.summaryEnabled)
        #expect(preferences.summaryTime == .defaultMorning)
        #expect(preferences.issueAlertsEnabled)
        #expect(
            preferences.recordingConfigurationWarningRegistration
                == RecordingConfigurationWarningRegistration(),
        )
        #expect(preferences.driftThresholdMeters == DriftThreshold.default.rawValue)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == nil)
        #expect(preferences.lastWelcomedRegion == nil)
    }

    @Test(arguments: [
        (false, RemoteLoggingConfiguration.off),
        (
            true,
            RemoteLoggingConfiguration.enabled(
                minimumLevel: .warning,
                metadataPolicy: .approvedFields,
            )
        ),
    ])
    func diagnosticDefaults(
        isDebugBuild: Bool,
        expectedRemoteLogging: RemoteLoggingConfiguration,
    ) {
        let configuration = preferences().diagnosticReportingConfiguration(
            isDebugBuild: isDebugBuild,
        )

        #expect(configuration.sharesCrashReports)
        #expect(configuration.sharesSessionReplays == false)
        #expect(configuration.remoteLogging == expectedRemoteLogging)
    }

    @Test func diagnosticConfigurationRoundTrips() throws {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)
        let configuration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .notice,
                metadataPolicy: .allMetadataExcludingAttachmentData,
            ),
        )

        preferences.diagnosticReportingConfiguration = configuration

        #expect(preferences.diagnosticReportingConfiguration == configuration)
        let data = try #require(
            store.object(forKey: "where.diagnostics.configuration") as? Data,
        )
        #expect(
            try JSONDecoder().decode(DiagnosticReportingConfiguration.self, from: data)
                == configuration,
        )
    }

    @Test func invalidDiagnosticValuesFailSafelyToRemoteLoggingOff() throws {
        let invalidLevel = try JSONSerialization.data(withJSONObject: [
            "shares_crash_reports": false,
            "shares_session_replays": true,
            "remote_logging": [
                "enabled": [
                    "minimum_level": "verbose",
                    "metadata_policy": "approvedFields",
                ],
            ],
        ])

        for value: Any in ["not data", Data("not JSON".utf8), invalidLevel] {
            let store = InMemoryKeyValueStore()
            store.set(value, forKey: "where.diagnostics.configuration")
            var messages: [String] = []
            let preferences = WherePreferences(
                store: store,
                invalidValue: { messages.append($0) },
            )

            let configuration = preferences.diagnosticReportingConfiguration
            #expect(configuration.sharesCrashReports)
            #expect(configuration.sharesSessionReplays == false)
            #expect(configuration.remoteLogging == .off)
            #expect(messages.count == 1)
        }
    }

    @Test func themeRoundTripsAndUnknownValuesFallBackToStandard() {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)

        preferences.theme = .alternate
        #expect(preferences.theme == .alternate)

        store.set("future-theme", forKey: "where.theme")
        #expect(preferences.theme == .standard)
    }

    @Test func locationDayCountsRoundTripIndependentlyByYear() {
        let preferences = preferences()
        let counts2025: [Region: Int] = [.california: 42, .other: 3]
        let counts2026: [Region: Int] = [.newYork: 81, .europeanUnion: 7]

        preferences.setLastSeenLocationDayCounts(counts2025, in: 2025)
        preferences.setLastSeenLocationDayCounts(counts2026, in: 2026)

        #expect(preferences.lastSeenLocationDayCounts(in: 2025) == counts2025)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == counts2026)
    }

    @Test func lastWelcomedRegionRoundTripsAndClears() {
        let preferences = preferences()

        preferences.lastWelcomedRegion = .newYork
        #expect(preferences.lastWelcomedRegion == .newYork)

        preferences.lastWelcomedRegion = nil
        #expect(preferences.lastWelcomedRegion == nil)
    }

    @Test func locationWelcomeVisibilityRoundTrips() {
        let preferences = preferences()

        preferences.showsLocationWelcome = false

        #expect(preferences.showsLocationWelcome == false)
    }

    @Test func estimatedTimeUsesTheLegacyLocationsVisibilityKey() {
        let store = InMemoryKeyValueStore()
        store.set(false, forKey: "where.showsLocationForecastsOnLocationsTab")
        let preferences = WherePreferences(store: store)

        #expect(preferences.showsEstimatedTimeAndPlanning == false)

        preferences.showsEstimatedTimeAndPlanning = true
        #expect(store.bool(forKey: "where.showsLocationForecastsOnLocationsTab"))
    }

    @Test func recordingWarningRegistrationRoundTrips() {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)
        var registration = RecordingConfigurationWarningRegistration()
        registration.register(isWarningConditionActive: true)
        registration.acknowledgeCurrentGeneration()

        preferences.recordingConfigurationWarningRegistration = registration

        #expect(preferences.recordingConfigurationWarningRegistration == registration)
        #expect(
            store.object(forKey: "where.recordingConfigurationWarningRegistration") is Data,
        )
    }

    @Test func invalidRecordingWarningRegistrationsUseDefault() throws {
        let invalidRegistration = try JSONSerialization.data(withJSONObject: [
            "generation": -1,
            "acknowledgedGeneration": 0,
        ])

        for value: Any in ["not data", Data("not JSON".utf8), invalidRegistration] {
            let store = InMemoryKeyValueStore()
            store.set(value, forKey: "where.recordingConfigurationWarningRegistration")
            var messages: [String] = []
            let preferences = WherePreferences(
                store: store,
                invalidValue: { messages.append($0) },
            )

            #expect(
                preferences.recordingConfigurationWarningRegistration
                    == RecordingConfigurationWarningRegistration(),
            )
            #expect(messages.count == 1)
        }
    }

    @Test func resetRestoresEveryDefaultAndClearsLocationCounts() {
        let preferences = preferences()
        preferences.hasOnboarded = true
        preferences.showsRecordedLocationDots = false
        preferences.showsLocationWelcome = false
        preferences.theme = .alternate
        preferences.showsEstimatedTimeAndPlanning = false
        preferences.remindersEnabled = false
        preferences.reminderTime = ReminderTime(hour: 9, minute: 15)
        preferences.summaryEnabled = false
        preferences.summaryTime = ReminderTime(hour: 17, minute: 45)
        preferences.issueAlertsEnabled = false
        var recordingWarning = preferences.recordingConfigurationWarningRegistration
        recordingWarning.register(isWarningConditionActive: true)
        recordingWarning.acknowledgeCurrentGeneration()
        preferences.recordingConfigurationWarningRegistration = recordingWarning
        preferences.driftThresholdMeters = 25000
        preferences.setLastSeenLocationDayCounts([.california: 100], in: 2026)
        preferences.lastWelcomedRegion = .california
        preferences.diagnosticReportingConfiguration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                metadataPolicy: .allMetadataExcludingAttachmentData,
            ),
        )

        preferences.reset()

        #expect(preferences.hasOnboarded == false)
        #expect(preferences.showsRecordedLocationDots)
        #expect(preferences.showsLocationWelcome)
        #expect(preferences.theme == .standard)
        #expect(preferences.showsEstimatedTimeAndPlanning)
        #expect(preferences.remindersEnabled)
        #expect(preferences.reminderTime == .defaultEvening)
        #expect(preferences.summaryEnabled)
        #expect(preferences.summaryTime == .defaultMorning)
        #expect(preferences.issueAlertsEnabled)
        #expect(
            preferences.recordingConfigurationWarningRegistration
                == RecordingConfigurationWarningRegistration(),
        )
        #expect(preferences.driftThresholdMeters == DriftThreshold.default.rawValue)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == nil)
        #expect(preferences.lastWelcomedRegion == nil)
        #expect(
            preferences.diagnosticReportingConfiguration
                == DiagnosticReportingConfiguration.currentBuildDefaults,
        )
    }
}
