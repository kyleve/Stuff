import SFSafeSymbols
import SwiftUI

struct DailyReminderSection: View {
    @Bindable var reminders: RemindersSettingsModel
    let openSettings: () -> Void

    var body: some View {
        Section {
            NotificationOptionToggle(
                isOn: $reminders.remindersEnabled,
                title: .settingsRemindersToggle,
                symbol: .bellBadge,
                item: .dailyReminder,
            )

            if reminders.remindersEnabled {
                WhereDatePicker(
                    String(localized: .settingsRemindersTime),
                    selection: $reminders.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    OpenNotificationSettingsButton(openSettings: openSettings)
                }
            }
        } header: {
            Text(String(localized: .settingsRemindersHeader))
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if reminders.remindersEnabled, !reminders.notificationsAuthorized {
            return String(localized: .settingsRemindersDeniedFooter)
        }
        return String(localized: .settingsRemindersFooter)
    }
}

#if DEBUG
    #Preview {
        Form { DailyReminderSection(
            reminders: PreviewSupport.remindersSettingsModel(),
            openSettings: {},
        ) }
        .whereBroadwayRoot()
    }
#endif
