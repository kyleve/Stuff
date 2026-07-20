import SwiftUI

/// Settings drill-in for the daily logging reminder: the toggle, the time of
/// day, and the notifications-permission affordance when they're off.
struct RemindersSettingsView: View {
    let reminders: RemindersSettingsModel
    var focus: SettingsFocus?

    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var reminders = reminders
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    Toggle(isOn: $reminders.remindersEnabled) {
                        Label(Strings.settingsRemindersToggle, systemImage: "bell.badge")
                    }
                    .settingsRow(Item.dailyReminder)

                    if reminders.remindersEnabled {
                        DatePicker(
                            Strings.settingsReminderTime,
                            selection: $reminders.reminderTimeOfDay,
                            displayedComponents: .hourAndMinute,
                        )

                        if !reminders.notificationsAuthorized {
                            Button {
                                openSystemSettings(openURL)
                            } label: {
                                Label(
                                    Strings.settingsRemindersOpenSettings,
                                    systemImage: "bell.slash",
                                )
                            }
                        }
                    }
                } header: {
                    Text(Strings.settingsRemindersHeader)
                } footer: {
                    Text(footer)
                }
            }
        }
        .navigationTitle(Strings.settingsRemindersHeader)
        .navigationBarTitleDisplayMode(.inline)
        // Notification permission can change in the Settings app while we're
        // away; refresh it when the screen appears so the "allow notifications"
        // affordance is accurate.
        .task { await reminders.refreshNotificationAuthorization() }
    }

    private var footer: String {
        if reminders.remindersEnabled, !reminders.notificationsAuthorized {
            return Strings.settingsRemindersDeniedFooter
        }
        return Strings.settingsRemindersFooter
    }
}

extension RemindersSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .reminders
    }

    enum Item: SettingsItem {
        case dailyReminder

        var title: String {
            switch self {
                case .dailyReminder: Strings.settingsRemindersToggle
            }
        }

        var keywords: [String] {
            switch self {
                case .dailyReminder: splitKeywords(Strings.settingsKeywordsReminder)
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RemindersSettingsView(reminders: PreviewSupport.remindersSettingsModel())
        }
        .whereBroadwayRoot()
    }
#endif
