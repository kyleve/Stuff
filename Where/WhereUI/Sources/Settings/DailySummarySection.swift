import SFSafeSymbols
import SwiftUI

struct DailySummarySection: View {
    @Bindable var reminders: RemindersSettingsModel
    let openSettings: () -> Void

    var body: some View {
        Section {
            NotificationOptionToggle(
                isOn: $reminders.summaryEnabled,
                title: .settingsSummaryToggle,
                symbol: .chartBarDocHorizontal,
                item: .dailySummary,
            )

            if reminders.summaryEnabled {
                WhereDatePicker(
                    String(localized: .settingsSummaryTime),
                    selection: $reminders.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    OpenNotificationSettingsButton(openSettings: openSettings)
                }
            }
        } header: {
            Text(String(localized: .settingsSummaryHeader))
        } footer: {
            Text(summaryFooter)
        }
    }

    private var summaryFooter: String {
        if reminders.summaryEnabled, !reminders.notificationsAuthorized {
            return String(localized: .settingsSummaryDeniedFooter)
        }
        return String(localized: .settingsSummaryFooter)
    }
}

#if DEBUG
    #Preview {
        Form { DailySummarySection(
            reminders: PreviewSupport.remindersSettingsModel(),
            openSettings: {},
        ) }
        .whereBroadwayRoot()
    }
#endif
