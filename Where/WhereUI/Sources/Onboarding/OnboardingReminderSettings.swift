import WhereCore

/// Setup draft for this phone's notification categories. Schedules retain their existing local
/// values; launch applies these choices independently of automatic recording.
struct OnboardingReminderSettings: Equatable {
    var remindersEnabled: Bool
    var issueAlertsEnabled: Bool
    var summaryEnabled: Bool

    init(preferences: WherePreferences) {
        remindersEnabled = preferences.remindersEnabled
        issueAlertsEnabled = preferences.issueAlertsEnabled
        summaryEnabled = preferences.summaryEnabled
    }

    func save(to preferences: WherePreferences) {
        preferences.remindersEnabled = remindersEnabled
        preferences.issueAlertsEnabled = issueAlertsEnabled
        preferences.summaryEnabled = summaryEnabled
    }
}
