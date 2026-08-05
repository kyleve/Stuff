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
        #expect(preferences.wantsTracking)
        #expect(preferences.remindersEnabled)
        #expect(preferences.reminderTime == .defaultEvening)
        #expect(preferences.summaryEnabled)
        #expect(preferences.summaryTime == .defaultMorning)
        #expect(preferences.issueAlertsEnabled)
        #expect(preferences.driftThresholdMeters == DriftThreshold.default.rawValue)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == nil)
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

    @Test func resetRestoresEveryDefaultAndClearsLocationCounts() {
        let preferences = preferences()
        preferences.hasOnboarded = true
        preferences.wantsTracking = false
        preferences.remindersEnabled = false
        preferences.reminderTime = ReminderTime(hour: 9, minute: 15)
        preferences.summaryEnabled = false
        preferences.summaryTime = ReminderTime(hour: 17, minute: 45)
        preferences.issueAlertsEnabled = false
        preferences.driftThresholdMeters = 25000
        preferences.setLastSeenLocationDayCounts([.california: 100], in: 2026)

        preferences.reset()

        #expect(preferences.hasOnboarded == false)
        #expect(preferences.wantsTracking)
        #expect(preferences.remindersEnabled)
        #expect(preferences.reminderTime == .defaultEvening)
        #expect(preferences.summaryEnabled)
        #expect(preferences.summaryTime == .defaultMorning)
        #expect(preferences.issueAlertsEnabled)
        #expect(preferences.driftThresholdMeters == DriftThreshold.default.rawValue)
        #expect(preferences.lastSeenLocationDayCounts(in: 2026) == nil)
    }
}
