import SwiftUI
import WhereCore

/// Settings drill-in combining the notification-driven alerts (the daily logging
/// reminder, the daily summary, and issue alerts) with the GPS data-resolution
/// threshold and the manual "find issues now" scan.
struct AlertsSettingsView: View {
    let report: YearReportModel
    let reminders: RemindersSettingsModel
    var focus: SettingsFocus?

    @Environment(\.openURL) private var openURL

    // "Find issues now": a manual, force-past-the-throttle data-issue scan and
    // its result (issue count) shown until the next scan.
    @State private var isScanningForIssues = false
    @State private var lastScanIssueCount: Int?

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                remindersSection
                summarySection
                issueAlertsSection
                dataResolutionSection
                findIssuesSection
            }
        }
        .navigationTitle(String(localized: .settingsAlertsGroup))
        .navigationBarTitleDisplayMode(.inline)
        // Notification permission can change in the Settings app while we're
        // away; refresh it when the screen appears so the "allow notifications"
        // affordance is accurate.
        .task { await reminders.refreshNotificationAuthorization() }
    }

    private var remindersSection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.remindersEnabled) {
                Label(String(localized: .settingsRemindersToggle), systemImage: "bell.badge")
            }
            .settingsRow(Item.dailyReminder)

            if reminders.remindersEnabled {
                WhereDatePicker(
                    String(localized: .settingsRemindersTime),
                    selection: $reminders.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings(openURL)
                    } label: {
                        Label(
                            String(localized: .settingsRemindersOpenSettings),
                            systemImage: "bell.slash",
                        )
                    }
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

    private var summarySection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.summaryEnabled) {
                Label(
                    String(localized: .settingsSummaryToggle),
                    systemImage: "chart.bar.doc.horizontal",
                )
            }
            .settingsRow(Item.dailySummary)

            if reminders.summaryEnabled {
                WhereDatePicker(
                    String(localized: .settingsSummaryTime),
                    selection: $reminders.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings(openURL)
                    } label: {
                        Label(
                            String(localized: .settingsRemindersOpenSettings),
                            systemImage: "bell.slash",
                        )
                    }
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

    private var issueAlertsSection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.issueAlertsEnabled) {
                Label(
                    String(localized: .settingsIssueAlertsToggle),
                    systemImage: "checklist.checked",
                )
            }
            .settingsRow(Item.issueAlerts)

            if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
                Button {
                    openSystemSettings(openURL)
                } label: {
                    Label(
                        String(localized: .settingsRemindersOpenSettings),
                        systemImage: "bell.slash",
                    )
                }
            }
        } header: {
            Text(String(localized: .settingsIssueAlertsHeader))
        } footer: {
            Text(issueAlertsFooter)
        }
    }

    private var issueAlertsFooter: String {
        if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
            return String(localized: .settingsIssueAlertsDeniedFooter)
        }
        return String(localized: .settingsIssueAlertsFooter)
    }

    private var dataResolutionSection: some View {
        @Bindable var report = report
        return Section {
            Picker(
                String(localized: .settingsResolutionThreshold),
                selection: $report.driftThreshold,
            ) {
                ForEach(DriftThreshold.allCases, id: \.self) { threshold in
                    Text(WhereFormat.driftThresholdLabel(kilometers: threshold.rawValue / 1000))
                        .tag(threshold)
                }
            }
            .settingsRow(Item.dataResolution)
        } header: {
            Text(String(localized: .settingsResolutionHeader))
        } footer: {
            Text(String(localized: .settingsResolutionFooter))
        }
    }

    private var findIssuesSection: some View {
        Section {
            Button {
                findIssues()
            } label: {
                if isScanningForIssues {
                    SavingStatusRow(text: String(localized: .settingsFindIssuesScanning))
                } else {
                    Label(String(localized: .settingsFindIssues), systemImage: "magnifyingglass")
                }
            }
            .disabled(isScanningForIssues)
            .settingsRow(Item.findIssues)

            if let count = lastScanIssueCount, !isScanningForIssues {
                Label {
                    Text(WhereFormat.settingsFindIssuesResult(count: count))
                } icon: {
                    Image(systemName: count == 0 ? "checkmark.circle" : "checklist")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: .settingsFindIssuesHeader))
        } footer: {
            Text(String(localized: .settingsFindIssuesFooter))
        }
        .animation(.default, value: isScanningForIssues)
        // The shown count is for the current year at the current threshold;
        // drop it once either changes so it can't linger as a stale result.
        .onChange(of: report.selectedYear) { lastScanIssueCount = nil }
        .onChange(of: report.driftThreshold) { lastScanIssueCount = nil }
    }

    /// Force a fresh data-issue scan past the ~3h throttle, then surface the
    /// resulting count. The scan also refreshes the Resolve tab's badge and
    /// reloads its list (see `YearReportModel.rescanForIssues()`).
    private func findIssues() {
        Task {
            isScanningForIssues = true
            lastScanIssueCount = nil
            await report.rescanForIssues()
            lastScanIssueCount = report.dataIssueCount
            isScanningForIssues = false
        }
    }
}

extension AlertsSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .alerts
    }

    enum Item: SettingsItem {
        case dailyReminder
        case dailySummary
        case issueAlerts
        case dataResolution
        case findIssues

        var title: String {
            switch self {
                case .dailyReminder: String(localized: .settingsRemindersToggle)
                case .dailySummary: String(localized: .settingsSummaryToggle)
                case .issueAlerts: String(localized: .settingsIssueAlertsToggle)
                case .dataResolution: String(localized: .settingsResolutionHeader)
                case .findIssues: String(localized: .settingsFindIssues)
            }
        }

        var keywords: [String] {
            switch self {
                case .dailyReminder: splitKeywords(String(localized: .settingsKeywordsReminder))
                case .dailySummary: splitKeywords(String(localized: .settingsKeywordsSummary))
                case .issueAlerts: splitKeywords(String(localized: .settingsKeywordsIssueAlerts))
                case .dataResolution: splitKeywords(
                        String(localized: .settingsKeywordsDataResolution),
                    )
                case .findIssues: splitKeywords(String(localized: .settingsKeywordsFindIssues))
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            AlertsSettingsView(
                report: PreviewSupport.loadedYearReportModel(),
                reminders: PreviewSupport.remindersSettingsModel(),
            )
        }
        .whereBroadwayRoot()
    }
#endif
