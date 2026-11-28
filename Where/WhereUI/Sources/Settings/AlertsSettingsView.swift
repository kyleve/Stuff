import SFSafeSymbols
import SwiftUI
import WhereCore

/// Settings drill-in combining the notification-driven alerts (the daily logging
/// reminder, the daily summary, and issue alerts) with the GPS data-resolution
/// threshold and the manual "find issues now" scan.
struct AlertsSettingsDestination: View {
    let report: YearReportModel
    let session: WhereSession
    var focus: SettingsFocus?

    var body: some View {
        ObservableHostingView {
            RemindersSettingsModel(session: session)
        } content: { reminders in
            AlertsSettingsView(report: report, reminders: reminders, focus: focus)
        }
    }
}

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
                DailyReminderSection(reminders: reminders, openSettings: openNotificationSettings)
                DailySummarySection(reminders: reminders, openSettings: openNotificationSettings)
                IssueAlertsSection(reminders: reminders, openSettings: openNotificationSettings)
                DataResolutionSection(report: report)
                FindIssuesSection(
                    isScanningForIssues: isScanningForIssues,
                    lastScanIssueCount: lastScanIssueCount,
                    scan: findIssues,
                )
                // The shown count is for the current year at the current threshold;
                // drop it once either changes so it can't linger as a stale result.
                .onChange(of: report.selectedYear) { lastScanIssueCount = nil }
                .onChange(of: report.driftThreshold) { lastScanIssueCount = nil }
            }
            .whereFormRoot()
        }
        .navigationTitle(String(localized: .settingsAlertsGroup))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reminders.authorizationRefreshTrigger) {
            await reminders.refreshNotificationAuthorization()
        }
    }

    private func openNotificationSettings() {
        openSystemSettings(openURL)
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

private struct IssueAlertsSection: View {
    @Bindable var reminders: RemindersSettingsModel
    let openSettings: () -> Void

    var body: some View {
        Section {
            NotificationOptionToggle(
                isOn: $reminders.issueAlertsEnabled,
                title: .settingsIssueAlertsToggle,
                symbol: .checklistChecked,
                item: .issueAlerts,
            )

            if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
                OpenNotificationSettingsButton(openSettings: openSettings)
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
}

struct OpenNotificationSettingsButton: View {
    let openSettings: () -> Void

    var body: some View {
        Button {
            openSettings()
        } label: {
            Label(
                String(localized: .settingsRemindersOpenSettings),
                systemSymbol: .bellSlash,
            )
        }
    }
}

struct NotificationOptionToggle: View {
    @Binding var isOn: Bool
    let title: LocalizedStringResource
    let symbol: SFSymbol
    let item: AlertsSettingsView.Item

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(String(localized: title), systemSymbol: symbol)
        }
        .settingsRow(item)
    }
}

private struct DataResolutionSection: View {
    @Bindable var report: YearReportModel

    var body: some View {
        Section {
            DriftThresholdPicker(threshold: $report.driftThreshold)
        } header: {
            Text(String(localized: .settingsResolutionHeader))
        } footer: {
            Text(String(localized: .settingsResolutionFooter))
        }
    }
}

private struct DriftThresholdPicker: View {
    @Binding var threshold: DriftThreshold

    var body: some View {
        Picker(
            String(localized: .settingsResolutionThreshold),
            selection: $threshold,
        ) {
            ForEach(DriftThreshold.allCases, id: \.self) { threshold in
                Text(WhereFormat.driftThresholdLabel(kilometers: threshold.rawValue / 1000))
                    .tag(threshold)
            }
        }
        .settingsRow(AlertsSettingsView.Item.dataResolution)
    }
}

private struct FindIssuesButton: View {
    let isScanning: Bool
    let scan: () -> Void

    var body: some View {
        Button {
            scan()
        } label: {
            if isScanning {
                SavingStatusRow(text: String(localized: .settingsFindIssuesScanning))
            } else {
                Label(String(localized: .settingsFindIssues), systemSymbol: .magnifyingglass)
            }
        }
        .disabled(isScanning)
        .settingsRow(AlertsSettingsView.Item.findIssues)
    }
}

private struct FindIssuesResult: View {
    let count: Int

    var body: some View {
        Label {
            Text(WhereFormat.settingsFindIssuesResult(count: count))
        } icon: {
            Image(systemSymbol: count == 0 ? .checkmarkCircle : .checklist)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct FindIssuesSection: View {
    let isScanningForIssues: Bool
    let lastScanIssueCount: Int?
    let scan: () -> Void

    var body: some View {
        Section {
            FindIssuesButton(isScanning: isScanningForIssues, scan: scan)

            if let count = lastScanIssueCount, !isScanningForIssues {
                FindIssuesResult(count: count)
            }
        } header: {
            Text(String(localized: .settingsFindIssuesHeader))
        } footer: {
            Text(String(localized: .settingsFindIssuesFooter))
        }
        .animation(.default, value: isScanningForIssues)
    }
}

#if DEBUG
    #Preview { AlertsSettingsPreview() }

    private struct AlertsSettingsPreview: View {
        var body: some View {
            NavigationStack {
                AlertsSettingsView(
                    report: PreviewSupport.loadedYearReportModel(),
                    reminders: PreviewSupport.remindersSettingsModel(),
                )
            }
            .whereBroadwayRoot()
        }
    }
#endif

#if DEBUG
    extension AlertsSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AlertsSettingsView.self,
            title: "Alerts Settings",
        ) { world in
            AlertsSettingsDestination(report: world.report, session: world.session)
        }
    }
#endif
