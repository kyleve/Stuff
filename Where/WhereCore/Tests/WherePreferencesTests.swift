import Foundation
import InstallerKit
import RegionKit
import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func persistsAndResetsInstallerCache() throws {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)
        let catalog = try JSONDecoder().decode(
            UpdateCatalog.self,
            from: Data(#"{"schemaVersion":3,"apps":[]}"#.utf8),
        )
        let value = try UpdatePreferences(cached: .init(
            feedURL: #require(URL(string: "https://example.org/updates.json")),
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000),
            catalog: catalog,
        ))
        preferences.installerUpdates = value
        #expect(WherePreferences(store: store).installerUpdates == value)
        preferences.reset()
        #expect(preferences.installerUpdates == UpdatePreferences(cached: nil))
    }

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
        #expect(preferences.locationWelcomeHistory == nil)
    }

    @Test(arguments: [
        (false, RemoteLoggingConfiguration.off),
        (
            true,
            RemoteLoggingConfiguration.enabled(
                minimumLevel: .warning,
                exportPolicy: .init(mode: .baseline, enabledControls: []),
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
                exportPolicy: .init(
                    mode: .diagnostic,
                    enabledControls: RemoteLoggingConfiguration.personalDataControls,
                ),
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

    @Test(arguments: WhereTheme.allCases)
    func themeRoundTripsAndUnknownValuesFallBackToStandard(theme: WhereTheme) {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)

        preferences.theme = theme
        #expect(WherePreferences(store: store).theme == theme)

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

    @Test func calendarZoomChoicesRoundTripIndependentlyAndReset() {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)
        let custom = CalendarZoomKey(rawValue: "travel-planner")
        #expect(preferences.calendarOverview(forKey: .year) == nil)

        preferences.setCalendarOverview(true, forKey: .year)
        preferences.setCalendarOverview(false, forKey: .region(.california))
        preferences.setCalendarOverview(true, forKey: .region(.newYork))
        preferences.setCalendarOverview(false, forKey: custom)

        let restored = WherePreferences(store: store)
        #expect(restored.calendarOverview(forKey: .year) == true)
        #expect(restored.calendarOverview(forKey: .region(.california)) == false)
        #expect(restored.calendarOverview(forKey: .region(.newYork)) == true)
        #expect(restored.calendarOverview(forKey: custom) == false)
        #expect(restored.calendarOverview(forKey: .region(.europeanUnion)) == nil)

        restored.reset()
        #expect(preferences.calendarOverview(forKey: .year) == nil)
        #expect(preferences.calendarOverview(forKey: .region(.california)) == nil)
        #expect(preferences.calendarOverview(forKey: .region(.newYork)) == nil)
        #expect(preferences.calendarOverview(forKey: custom) == nil)
    }

    @Test func invalidCalendarZoomEntryDoesNotHideOtherCalendars() {
        let store = InMemoryKeyValueStore()
        store.set(["year": "invalid", "region.us-CA": true], forKey: "where.calendarOverview")
        let preferences = WherePreferences(store: store)
        #expect(preferences.calendarOverview(forKey: .year) == nil)
        #expect(preferences.calendarOverview(forKey: .region(.california)) == true)

        preferences.setCalendarOverview(false, forKey: .year)
        #expect(preferences.calendarOverview(forKey: .year) == false)
        #expect(preferences.calendarOverview(forKey: .region(.california)) == true)
    }

    @Test(arguments: [Region.newYork, nil])
    func locationWelcomeHistoryRoundTripsAndClears(region: Region?) {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)

        preferences.locationWelcomeHistory = .init(lastRegion: region)
        #expect(
            WherePreferences(store: store).locationWelcomeHistory == .init(lastRegion: region),
        )

        preferences.locationWelcomeHistory = nil
        #expect(WherePreferences(store: store).locationWelcomeHistory == nil)
    }

    @Test func formerWelcomeAcknowledgementDoesNotReplaceTheInitialLiveBaseline() {
        let store = InMemoryKeyValueStore()
        store.set(Region.california.rawValue, forKey: "where.lastWelcomedRegion")
        let preferences = WherePreferences(store: store)

        #expect(preferences.locationWelcomeHistory == nil)

        preferences.reset()
        #expect(store.object(forKey: "where.lastWelcomedRegion") == nil)
    }

    @Test func invalidWelcomeHistoryRequiresAQuietBaseline() {
        let store = InMemoryKeyValueStore()
        store.set(Data("not JSON".utf8), forKey: "where.locationWelcomeHistory")
        var messages: [String] = []
        let preferences = WherePreferences(store: store, invalidValue: { messages.append($0) })

        #expect(preferences.locationWelcomeHistory == nil)
        #expect(messages.count == 1)
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
        preferences.locationWelcomeHistory = .init(lastRegion: .california)
        preferences.diagnosticReportingConfiguration = DiagnosticReportingConfiguration(
            sharesCrashReports: false,
            sharesSessionReplays: true,
            remoteLogging: .enabled(
                minimumLevel: .debug,
                exportPolicy: .init(
                    mode: .diagnostic,
                    enabledControls: RemoteLoggingConfiguration.personalDataControls,
                ),
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
        #expect(preferences.locationWelcomeHistory == nil)
        #expect(
            preferences.diagnosticReportingConfiguration
                == DiagnosticReportingConfiguration.currentBuildDefaults,
        )
    }
}
