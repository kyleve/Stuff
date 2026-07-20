import SwiftUI
import WhereCore

/// Settings drill-in combining the notification-driven alerts (daily summary,
/// issue alerts) with the GPS data-resolution threshold and the manual
/// "find issues now" scan.
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
                summarySection
                issueAlertsSection
                resolutionSection
            }
        }
        .navigationTitle(Strings.settingsAlertsGroup)
        .navigationBarTitleDisplayMode(.inline)
        // Notification permission can change in the Settings app while we're
        // away; refresh it when the screen appears so the "allow notifications"
        // affordance is accurate.
        .task { await reminders.refreshNotificationAuthorization() }
    }

    private var summarySection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.summaryEnabled) {
                Label(Strings.settingsSummaryToggle, systemImage: "chart.bar.doc.horizontal")
            }
            .settingsRow(Item.dailySummary)

            if reminders.summaryEnabled {
                DatePicker(
                    Strings.settingsSummaryTime,
                    selection: $reminders.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings(openURL)
                    } label: {
                        Label(Strings.settingsRemindersOpenSettings, systemImage: "bell.slash")
                    }
                }
            }
        } header: {
            Text(Strings.settingsSummaryHeader)
        } footer: {
            Text(summaryFooter)
        }
    }

    private var summaryFooter: String {
        if reminders.summaryEnabled, !reminders.notificationsAuthorized {
            return Strings.settingsSummaryDeniedFooter
        }
        return Strings.settingsSummaryFooter
    }

    private var issueAlertsSection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.issueAlertsEnabled) {
                Label(Strings.settingsIssueAlertsToggle, systemImage: "checklist.checked")
            }
            .settingsRow(Item.issueAlerts)

            if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
                Button {
                    openSystemSettings(openURL)
                } label: {
                    Label(Strings.settingsRemindersOpenSettings, systemImage: "bell.slash")
                }
            }
        } header: {
            Text(Strings.settingsIssueAlertsHeader)
        } footer: {
            Text(issueAlertsFooter)
        }
    }

    private var issueAlertsFooter: String {
        if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
            return Strings.settingsIssueAlertsDeniedFooter
        }
        return Strings.settingsIssueAlertsFooter
    }

    private var resolutionSection: some View {
        @Bindable var report = report
        return Section {
            Picker(Strings.settingsResolutionHeader, selection: $report.driftThreshold) {
                ForEach(DriftThreshold.allCases, id: \.self) { threshold in
                    Text(Strings.driftThresholdLabel(kilometers: threshold.rawValue / 1000))
                        .tag(threshold)
                }
            }
            .settingsRow(Item.dataResolution)

            Button {
                findIssues()
            } label: {
                if isScanningForIssues {
                    SavingStatusRow(text: Strings.settingsFindIssuesScanning)
                } else {
                    Label(Strings.settingsFindIssues, systemImage: "magnifyingglass")
                }
            }
            .disabled(isScanningForIssues)
            .settingsRow(Item.findIssues)

            if let count = lastScanIssueCount, !isScanningForIssues {
                Label {
                    Text(Strings.settingsFindIssuesResult(count: count))
                } icon: {
                    Image(systemName: count == 0 ? "checkmark.circle" : "checklist")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } footer: {
            Text(Strings.settingsResolutionFooter)
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
        case dailySummary
        case issueAlerts
        case dataResolution
        case findIssues

        var title: String {
            switch self {
                case .dailySummary: Strings.settingsSummaryToggle
                case .issueAlerts: Strings.settingsIssueAlertsToggle
                case .dataResolution: Strings.settingsResolutionHeader
                case .findIssues: Strings.settingsFindIssues
            }
        }

        var keywords: [String] {
            switch self {
                case .dailySummary: splitKeywords(Strings.settingsKeywordsSummary)
                case .issueAlerts: splitKeywords(Strings.settingsKeywordsIssueAlerts)
                case .dataResolution: splitKeywords(Strings.settingsKeywordsDataResolution)
                case .findIssues: splitKeywords(Strings.settingsKeywordsFindIssues)
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
