import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func resetRestoresFirstInstallDefaults() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.hasOnboarded = true
        preferences.remindersEnabled = false
        preferences.reminderTime = ReminderTime(hour: 1, minute: 2)
        preferences.summaryEnabled = false
        preferences.summaryTime = ReminderTime(hour: 3, minute: 4)
        preferences.issueAlertsEnabled = false
        preferences.driftThresholdMeters = 123

        preferences.reset()

        #expect(preferences.hasOnboarded == false)
        #expect(preferences.remindersEnabled)
        #expect(preferences.reminderTime == .defaultEvening)
        #expect(preferences.summaryEnabled)
        #expect(preferences.summaryTime == .defaultMorning)
        #expect(preferences.issueAlertsEnabled)
        #expect(preferences.driftThresholdMeters == DriftThreshold.default.rawValue)
    }
}
