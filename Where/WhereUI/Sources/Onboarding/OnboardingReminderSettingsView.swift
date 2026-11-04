import SwiftUI

/// Local notification choices, presented independently of the recording toggle.
struct OnboardingReminderSettingsView: View {
    @Binding var settings: OnboardingReminderSettings
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            Text(String(localized: .onboardingRemindersTitle))
                .font(.headline)
            Toggle(String(localized: .settingsRemindersToggle), isOn: $settings.remindersEnabled)
            Toggle(
                String(localized: .settingsIssueAlertsToggle),
                isOn: $settings.issueAlertsEnabled,
            )
            Toggle(String(localized: .settingsSummaryToggle), isOn: $settings.summaryEnabled)
            Text(String(localized: .onboardingRemindersDescription))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        OnboardingReminderSettingsView(settings: .constant(
            OnboardingReminderSettings(preferences: PreviewSupport.previewPreferences()),
        ))
        .padding()
    }
#endif
