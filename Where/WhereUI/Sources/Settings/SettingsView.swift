import LifecycleKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WhereCore

/// Settings tab: location permission + tracking, retroactive manual entry,
/// whole-database backup export/import, and the destructive "erase a year"
/// action.
struct SettingsView: View {
    // The scene's report model drives the year-scoped rows (clear-year, drift
    // threshold); the always-on `WhereSession` coordinator (environment) drives
    // tracking/permission; `model` (environment) drives the reset sequence (which
    // rebuilds the session from scratch). The reminder and backup editing
    // surfaces are view-scoped models owned here.
    let report: YearReportModel
    @State private var backup: BackupModel
    @State private var reminders: RemindersSettingsModel

    @Environment(WhereModel.self) private var model
    @Environment(WhereSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.lifecycleRunner) private var runner

    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showAppIcon = false

    // Backup import: the picked file, the merge/replace choice, and the
    // success confirmation.
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showStrategyDialog = false
    @State private var showImportSuccess = false
    @State private var lastImportSummary: BackupCoordinator.ImportSummary?

    init(report: YearReportModel) {
        self.report = report
        _backup = State(initialValue: BackupModel(services: report.services))
        _reminders = State(initialValue: RemindersSettingsModel(
            services: report.services,
            preferences: report.preferences,
            now: report.now,
        ))
    }

    var body: some View {
        @Bindable var session = session
        @Bindable var backup = backup

        NavigationStack {
            Form {
                trackingSection
                remindersSection
                summarySection
                issueAlertsSection
                resolutionSection
                tabsSection
                appIconSection
                manualEntrySection
                backupSection
                dataSection
                resetSection
            }
            .navigationTitle(String(localized: .settingsTitle))
            // Notification permission can change in the Settings app while we're
            // away; refresh it when the screen appears so the "open Settings"
            // affordance is accurate.
            .task { await reminders.refreshNotificationAuthorization() }
            .sheet(isPresented: $showAppIcon) {
                AppIconView()
            }
            .alert(
                String(localized: .settingsPermissionAlertTitle),
                isPresented: $session.permissionDenied,
            ) {
                Button(.settingsPermissionAlertOpenSettings) { openSystemSettings() }
                Button(.settingsPermissionAlertNotNow, role: .cancel) {}
            } message: {
                Text(.settingsPermissionAlertMessage)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip],
                onCompletion: handleImportSelection,
            )
            .confirmationDialog(
                String(localized: .settingsBackupImportStrategyTitle),
                isPresented: $showStrategyDialog,
                titleVisibility: .visible,
                presenting: pendingImportURL,
            ) { url in
                Button(.settingsBackupMerge) { runImport(url: url, strategy: .merge) }
                Button(.settingsBackupReplace, role: .destructive) {
                    runImport(url: url, strategy: .replace)
                }
                Button(.settingsDataCancel, role: .cancel) { pendingImportURL = nil }
            } message: { _ in
                Text(.settingsBackupImportStrategyMessage)
            }
            .alert(
                String(localized: .settingsBackupImportedTitle),
                isPresented: $showImportSuccess,
                presenting: lastImportSummary,
            ) { _ in
                Button(.commonOk, role: .cancel) {}
            } message: { summary in
                Text(.settingsBackupImportedMessage(
                    summary.sampleCount,
                    summary.evidenceCount,
                    summary.manualDayCount,
                    summary.dismissedIssueCount,
                ))
            }
            .alert(
                String(localized: .settingsBackupErrorTitle),
                isPresented: $backup.isShowingBackupError,
                presenting: backup.backupError,
            ) { _ in
                Button(.commonOk, role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var trackingSection: some View {
        @Bindable var session = session
        return Section {
            LocationStatusRow(status: session.authorizationStatus, isTracking: session.isTracking)

            Toggle(isOn: $session.trackingEnabled) {
                Label(.settingsLocationToggle, systemImage: "location.fill")
            }

            if showGrantButton {
                Button {
                    Task { await session.requestPermission() }
                } label: {
                    Label(.settingsLocationGrant, systemImage: "location.magnifyingglass")
                }
            }

            if showOpenSettingsButton {
                Button {
                    openSystemSettings()
                } label: {
                    Label(.settingsPermissionAlertOpenSettings, systemImage: "gear")
                }
            }
        } header: {
            Text(.settingsLocationHeader)
        } footer: {
            Text(.settingsLocationFooter)
        }
    }

    /// Re-requesting only helps before the user has made a final decision.
    private var showGrantButton: Bool {
        switch session.authorizationStatus {
            case .notDetermined, .whenInUse: true
            case .restricted, .denied, .always: false
        }
    }

    /// Once access is denied/restricted (or stuck at When-In-Use), the only way
    /// forward is the Settings app.
    private var showOpenSettingsButton: Bool {
        switch session.authorizationStatus {
            case .denied, .restricted, .whenInUse: true
            case .notDetermined, .always: false
        }
    }

    private var remindersSection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.remindersEnabled) {
                Label(.settingsRemindersToggle, systemImage: "bell.badge")
            }

            if reminders.remindersEnabled {
                DatePicker(
                    String(localized: .settingsRemindersTime),
                    selection: $reminders.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(.settingsRemindersOpenSettings, systemImage: "bell.slash")
                    }
                }
            }
        } header: {
            Text(.settingsRemindersHeader)
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
                Label(.settingsSummaryToggle, systemImage: "chart.bar.doc.horizontal")
            }

            if reminders.summaryEnabled {
                DatePicker(
                    String(localized: .settingsSummaryTime),
                    selection: $reminders.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(.settingsRemindersOpenSettings, systemImage: "bell.slash")
                    }
                }
            }
        } header: {
            Text(.settingsSummaryHeader)
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
                Label(.settingsIssueAlertsToggle, systemImage: "checklist.checked")
            }

            if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
                Button {
                    openSystemSettings()
                } label: {
                    Label(.settingsRemindersOpenSettings, systemImage: "bell.slash")
                }
            }
        } header: {
            Text(.settingsIssueAlertsHeader)
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

    private var resolutionSection: some View {
        @Bindable var report = report

        return Section {
            Picker(
                String(localized: .settingsResolutionHeader),
                selection: $report.driftThreshold,
            ) {
                ForEach(DriftThreshold.allCases, id: \.self) { threshold in
                    Text(WhereFormat.driftThreshold(kilometers: threshold.rawValue / 1000))
                        .tag(threshold)
                }
            }
        } footer: {
            Text(.settingsResolutionFooter)
        }
    }

    private var tabsSection: some View {
        @Bindable var report = report
        return Section {
            Toggle(isOn: $report.hideEmptyTabs) {
                Label(.settingsTabsToggle, systemImage: "rectangle.bottomthird.inset.filled")
            }
        } header: {
            Text(.settingsTabsHeader)
        } footer: {
            Text(.settingsTabsFooter)
        }
    }

    private var appIconSection: some View {
        Section {
            Button {
                showAppIcon = true
            } label: {
                Label(.settingsAppIconLink, systemImage: "app.badge")
            }
        } header: {
            Text(.settingsAppIconHeader)
        } footer: {
            Text(.settingsAppIconFooter)
        }
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView(report: report)
            } label: {
                Label(.settingsManualLink, systemImage: "calendar.badge.plus")
            }
        } header: {
            Text(.settingsManualHeader)
        } footer: {
            Text(.settingsManualFooter)
        }
    }

    private var backupSection: some View {
        Section {
            // `ShareLink` builds the archive lazily through `BackupArchiveFile`
            // and presents the native share sheet (with its own export
            // progress), so no custom `UIActivityViewController` is needed.
            ShareLink(
                item: backupArchiveFile,
                preview: SharePreview(String(localized: .settingsBackupShareTitle)),
            ) {
                Label(.settingsBackupExport, systemImage: "square.and.arrow.up")
            }
            .disabled(backup.backupState != .idle)

            Button {
                showImporter = true
            } label: {
                if backup.backupState == .importing {
                    importProgressLabel
                } else {
                    Label(.settingsBackupImport, systemImage: "square.and.arrow.down")
                }
            }
            .disabled(backup.backupState != .idle)
        } header: {
            Text(.settingsBackupHeader)
        } footer: {
            Text(.settingsBackupFooter)
        }
    }

    /// Determinate progress for an in-flight import, driven by
    /// `backup.backupProgress` as the backup coordinator writes each row.
    private var importProgressLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(.settingsBackupImporting, systemImage: "square.and.arrow.down")
            ProgressView(value: backup.backupProgress)
        }
    }

    /// Lazily-built backup for `ShareLink`. The closure runs only when the
    /// share sheet resolves the item; a failed export sets `backup.backupError`
    /// (surfacing the alert) and throws to abort the share.
    private var backupArchiveFile: BackupArchiveFile {
        BackupArchiveFile { [backup] in
            guard let url = await backup.exportBackup() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return url
        }
    }

    private func handleImportSelection(_ result: Result<URL, any Error>) {
        switch result {
            case let .success(url):
                pendingImportURL = url
                showStrategyDialog = true
            case let .failure(error):
                backup.backupError = error.localizedDescription
        }
    }

    private func runImport(url: URL, strategy: BackupCoordinator.ImportStrategy) {
        Task {
            if let summary = await backup.importBackup(from: url, strategy: strategy) {
                lastImportSummary = summary
                showImportSuccess = true
            }
            pendingImportURL = nil
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(eraseTitle, systemImage: "trash")
            }
            .confirmationDialog(
                eraseTitle,
                isPresented: $showClearConfirmation,
                titleVisibility: .visible,
            ) {
                Button(eraseTitle, role: .destructive) {
                    Task { await report.clearSelectedYear() }
                }
                Button(.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(.settingsDataConfirmMessage(WhereFormat.year(report.selectedYear)))
            }
        } header: {
            Text(.settingsDataHeader)
        } footer: {
            Text(.settingsDataFooter(WhereFormat.year(report.selectedYear)))
        }
    }

    private var eraseTitle: String {
        String(localized: .settingsDataErase(WhereFormat.year(report.selectedYear)))
    }

    /// Whole-app teardown: wipes every year's data and returns to first-run
    /// onboarding, run through the `LifecycleRunner` published into the
    /// environment by `LifecycleContainer`. The runner proxy asserts in debug /
    /// no-ops in release when no container is above (e.g. previews).
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(.settingsResetErase, systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog(
                String(localized: .settingsResetErase),
                isPresented: $showResetConfirmation,
                titleVisibility: .visible,
            ) {
                Button(.settingsResetConfirm, role: .destructive) {
                    requestReset()
                }
                Button(.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(.settingsResetMessage)
            }
        } footer: {
            Text(.settingsResetFooter)
        }
    }

    private func requestReset() {
        Task { await runner.teardown(WhereLaunch.resetSequence(for: model)) }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#if DEBUG
    #Preview {
        SettingsView(report: PreviewSupport.loadedYearReportModel())
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }
#endif
