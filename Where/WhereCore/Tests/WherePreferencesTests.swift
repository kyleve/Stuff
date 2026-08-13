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
        #expect(preferences.theme == .standard)
        #expect(preferences.showsLocationForecastsOnLocationsTab)
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

    @Test func recordingWarningRegistrationRoundTrips() {
        let preferences = preferences()
        var registration = RecordingConfigurationWarningRegistration()
        registration.register(isWarningConditionActive: true)
        registration.acknowledgeCurrentGeneration()

        preferences.recordingConfigurationWarningRegistration = registration

        #expect(preferences.recordingConfigurationWarningRegistration == registration)
    }

    @Test func resetRestoresEveryDefaultAndClearsLocationCounts() {
        let preferences = preferences()
        preferences.hasOnboarded = true
        preferences.showsRecordedLocationDots = false
        preferences.theme = .alternate
        preferences.showsLocationForecastsOnLocationsTab = false
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

        preferences.reset()

        #expect(preferences.hasOnboarded == false)
        #expect(preferences.showsRecordedLocationDots)
        #expect(preferences.theme == .standard)
        #expect(preferences.showsLocationForecastsOnLocationsTab)
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
    }
}
