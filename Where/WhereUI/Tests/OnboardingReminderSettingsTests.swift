import Testing
import WhereCore
@testable import WhereUI

struct OnboardingReminderSettingsTests {
    @Test func enabledDefaultsAndEditsStayLocalAndDoNotChangeSchedules() {
        let first = makePreferences()
        let second = makePreferences()
        first.reminderTime = ReminderTime(hour: 20, minute: 15)
        var draft = OnboardingReminderSettings(preferences: first)
        #expect(draft.remindersEnabled && draft.issueAlertsEnabled && draft.summaryEnabled)
        draft.remindersEnabled = false
        draft.issueAlertsEnabled = false
        draft.summaryEnabled = false
        #expect(first.remindersEnabled)
        draft.save(to: first)
        #expect(!first.remindersEnabled && !first.issueAlertsEnabled && !first.summaryEnabled)
        #expect(first.reminderTime == ReminderTime(hour: 20, minute: 15))
        #expect(second.remindersEnabled && second.issueAlertsEnabled && second.summaryEnabled)
    }
}
