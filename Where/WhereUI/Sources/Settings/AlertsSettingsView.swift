import SFSafeSymbols
import SnapshotKit
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

    @State private var issueSearch: IssueSearchModel

    init(report: YearReportModel, reminders: RemindersSettingsModel, focus: SettingsFocus? = nil) {
        self.report = report
        self.reminders = reminders
        self.focus = focus
        _issueSearch = State(initialValue: IssueSearchModel(report: report))
    }

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                remindersSection
                summarySection
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
                Label(String(localized: .settingsRemindersToggle), systemSymbol: .bellBadge)
            }
            .settingsRow(Item.dailyReminder)

            Toggle(isOn: $reminders.issueAlertsEnabled) {
                Label(
                    String(localized: .settingsIssueAlertsToggle),
                    systemSymbol: .checklistChecked,
                )
            }
            .settingsRow(Item.issueAlerts)

            if reminders.remindersEnabled || reminders.issueAlertsEnabled {
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
                            systemSymbol: .bellSlash,
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
        if reminders.remindersEnabled || reminders.issueAlertsEnabled,
           !reminders.notificationsAuthorized
        {
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
                    systemSymbol: .chartBarDocHorizontal,
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
                            systemSymbol: .bellSlash,
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
                Task { await issueSearch.scan() }
            } label: {
                if issueSearch.isScanning {
                    SavingStatusRow(text: String(localized: .settingsFindIssuesScanning))
                } else {
                    Label(String(localized: .settingsFindIssues), systemSymbol: .magnifyingglass)
                }
            }
            .disabled(issueSearch.isScanning)
            .settingsRow(Item.findIssues)

            switch issueSearch.state {
                case .idle, .scanning:
                    EmptyView()
                case let .complete(count):
                    Label {
                        Text(WhereFormat.settingsFindIssuesResult(count: count))
                    } icon: {
                        Image(systemSymbol: count == 0 ? .checkmarkCircle : .checklist)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                case let .failed(error):
                    Label(error.localizedDescription, systemSymbol: .exclamationmarkTriangle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: .settingsFindIssuesHeader))
        } footer: {
            Text(String(localized: .settingsFindIssuesFooter))
        }
        .animation(.default, value: issueSearch.isScanning)
        .onChange(of: report.driftThreshold) { issueSearch.invalidate() }
        .onDisappear { issueSearch.invalidate() }
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
    extension AlertsSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenRepresentative) {
                NavigationStack {
                    AlertsSettingsView(
                        report: PreviewSupport.loadedYearReportModel(),
                        reminders: PreviewSupport.remindersSettingsModel(),
                    )
                }
            }
            let issuesOnly = PreviewSupport.remindersSettingsModel(
                logging: false,
                issues: true,
                authorized: true,
            )
            whereSnapshot(
                name: "IssuesOnly",
                configurations: .fullContentPhoneLightDark,
                onReadyToMeasure: issuesOnly.refreshNotificationAuthorization,
            ) {
                NavigationStack {
                    AlertsSettingsView(
                        report: PreviewSupport.loadedYearReportModel(),
                        reminders: issuesOnly,
                    )
                }
            }
            let disabled = PreviewSupport.remindersSettingsModel(
                logging: false,
                issues: false,
                authorized: true,
            )
            whereSnapshot(
                name: "EveningDisabled",
                configurations: [.init(device: .iPhoneFullContent)],
                onReadyToMeasure: disabled.refreshNotificationAuthorization,
            ) {
                NavigationStack {
                    AlertsSettingsView(
                        report: PreviewSupport.loadedYearReportModel(),
                        reminders: disabled,
                    )
                }
            }
        }
    }

    #Preview {
        AlertsSettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension AlertsSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AlertsSettingsView.self,
            title: "Alerts Settings",
        ) { world in
            AlertsSettingsView(
                report: world.report,
                reminders: world.reminders,
            )
        }
    }
#endif
