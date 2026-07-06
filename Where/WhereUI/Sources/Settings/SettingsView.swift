import LifecycleKit
import LogViewerUI
#if DEBUG
    import SwiftDataInspector
#endif
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
    // tracking/permission + the DEBUG inspector; `model` (environment) drives
    // the reset sequence (which rebuilds the session from scratch). The reminder
    // and backup editing surfaces are view-scoped models owned here.
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
                appIconSection
                manualEntrySection
                backupSection
                dataSection
                resetSection
                #if DEBUG
                    developerSection
                #endif
            }
            .navigationTitle(Strings.settingsTitle)
            // Notification permission can change in the Settings app while we're
            // away; refresh it when the screen appears so the "open Settings"
            // affordance is accurate.
            .task { await reminders.refreshNotificationAuthorization() }
            .sheet(isPresented: $showAppIcon) {
                AppIconView()
            }
            .alert(Strings.settingsPermissionAlertTitle, isPresented: $session.permissionDenied) {
                Button(Strings.settingsPermissionAlertOpenSettings) { openSystemSettings() }
                Button(Strings.settingsPermissionAlertNotNow, role: .cancel) {}
            } message: {
                Text(Strings.settingsPermissionAlertMessage)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip],
                onCompletion: handleImportSelection,
            )
            .confirmationDialog(
                Strings.settingsBackupImportStrategyTitle,
                isPresented: $showStrategyDialog,
                titleVisibility: .visible,
                presenting: pendingImportURL,
            ) { url in
                Button(Strings.settingsBackupMerge) { runImport(url: url, strategy: .merge) }
                Button(Strings.settingsBackupReplace, role: .destructive) {
                    runImport(url: url, strategy: .replace)
                }
                Button(Strings.settingsDataCancel, role: .cancel) { pendingImportURL = nil }
            } message: { _ in
                Text(Strings.settingsBackupImportStrategyMessage)
            }
            .alert(
                Strings.settingsBackupImportedTitle,
                isPresented: $showImportSuccess,
                presenting: lastImportSummary,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) {}
            } message: { summary in
                Text(Strings.settingsBackupImportedMessage(
                    samples: summary.sampleCount,
                    evidence: summary.evidenceCount,
                    manualDays: summary.manualDayCount,
                    dismissedIssues: summary.dismissedIssueCount,
                ))
            }
            .alert(
                Strings.settingsBackupErrorTitle,
                isPresented: $backup.isShowingBackupError,
                presenting: backup.backupError,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) {}
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
                Label(Strings.settingsLocationToggle, systemImage: "location.fill")
            }

            if showGrantButton {
                Button {
                    Task { await session.requestPermission() }
                } label: {
                    Label(Strings.settingsLocationGrant, systemImage: "location.magnifyingglass")
                }
            }

            if showOpenSettingsButton {
                Button {
                    openSystemSettings()
                } label: {
                    Label(Strings.settingsPermissionAlertOpenSettings, systemImage: "gear")
                }
            }
        } header: {
            Text(Strings.settingsLocationHeader)
        } footer: {
            Text(Strings.settingsLocationFooter)
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
                Label(Strings.settingsRemindersToggle, systemImage: "bell.badge")
            }

            if reminders.remindersEnabled {
                DatePicker(
                    Strings.settingsReminderTime,
                    selection: $reminders.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(Strings.settingsRemindersOpenSettings, systemImage: "bell.slash")
                    }
                }
            }
        } header: {
            Text(Strings.settingsRemindersHeader)
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if reminders.remindersEnabled, !reminders.notificationsAuthorized {
            return Strings.settingsRemindersDeniedFooter
        }
        return Strings.settingsRemindersFooter
    }

    private var summarySection: some View {
        @Bindable var reminders = reminders
        return Section {
            Toggle(isOn: $reminders.summaryEnabled) {
                Label(Strings.settingsSummaryToggle, systemImage: "chart.bar.doc.horizontal")
            }

            if reminders.summaryEnabled {
                DatePicker(
                    Strings.settingsSummaryTime,
                    selection: $reminders.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !reminders.notificationsAuthorized {
                    Button {
                        openSystemSettings()
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

            if reminders.issueAlertsEnabled, !reminders.notificationsAuthorized {
                Button {
                    openSystemSettings()
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
        } footer: {
            Text(Strings.settingsResolutionFooter)
        }
    }

    private var appIconSection: some View {
        Section {
            Button {
                showAppIcon = true
            } label: {
                Label(Strings.settingsAppIconLink, systemImage: "app.badge")
            }
        } header: {
            Text(Strings.settingsAppIconHeader)
        } footer: {
            Text(Strings.settingsAppIconFooter)
        }
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView(report: report)
            } label: {
                Label(Strings.settingsManualLink, systemImage: "calendar.badge.plus")
            }
        } header: {
            Text(Strings.settingsManualHeader)
        } footer: {
            Text(Strings.settingsManualFooter)
        }
    }

    private var backupSection: some View {
        Section {
            // `ShareLink` builds the archive lazily through `BackupArchiveFile`
            // and presents the native share sheet (with its own export
            // progress), so no custom `UIActivityViewController` is needed.
            ShareLink(
                item: backupArchiveFile,
                preview: SharePreview(Strings.settingsBackupShareTitle),
            ) {
                Label(Strings.settingsBackupExport, systemImage: "square.and.arrow.up")
            }
            .disabled(backup.backupState != .idle)

            Button {
                showImporter = true
            } label: {
                if backup.backupState == .importing {
                    importProgressLabel
                } else {
                    Label(Strings.settingsBackupImport, systemImage: "square.and.arrow.down")
                }
            }
            .disabled(backup.backupState != .idle)
        } header: {
            Text(Strings.settingsBackupHeader)
        } footer: {
            Text(Strings.settingsBackupFooter)
        }
    }

    /// Determinate progress for an in-flight import, driven by
    /// `backup.backupProgress` as the backup coordinator writes each row.
    private var importProgressLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(Strings.settingsBackupImporting, systemImage: "square.and.arrow.down")
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
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsDataConfirmMessage(year: report.selectedYear))
            }
        } header: {
            Text(Strings.settingsDataHeader)
        } footer: {
            Text(Strings.settingsDataFooter(year: report.selectedYear))
        }
    }

    private var eraseTitle: String {
        Strings.settingsDataErase(year: report.selectedYear)
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
                Label(Strings.settingsResetErase, systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog(
                Strings.settingsResetErase,
                isPresented: $showResetConfirmation,
                titleVisibility: .visible,
            ) {
                Button(Strings.settingsResetConfirm, role: .destructive) {
                    requestReset()
                }
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsResetMessage)
            }
        } footer: {
            Text(Strings.settingsResetFooter)
        }
    }

    private func requestReset() {
        Task { await runner.teardown(WhereLaunch.resetSequence(for: model)) }
    }

    #if DEBUG
        /// Developer-only tools, compiled out of release: the in-app log viewer
        /// over the shared `WhereLog` buffer every logger writes to, plus — when
        /// the live session can vend a SwiftData container — the generic
        /// SwiftData inspector (previews and non-SwiftData fakes don't show it).
        private var developerSection: some View {
            Section {
                NavigationLink {
                    LogViewer(configuration: LogViewerConfiguration(
                        store: WhereLog.store,
                        title: Strings.settingsDebugLogsTitle,
                    ))
                } label: {
                    Label(Strings.settingsDebugLogsLink, systemImage: "ladybug")
                }

                if let configuration = session.swiftDataInspectorConfiguration {
                    NavigationLink {
                        SwiftDataInspectorView(configuration: configuration)
                    } label: {
                        Label(Strings.settingsDebugInspectorLink, systemImage: "cylinder.split.1x2")
                    }
                }

                NavigationLink {
                    RegionMapView()
                } label: {
                    Label(Strings.settingsDebugRegionMapLink, systemImage: "map")
                }
            } header: {
                Text(Strings.settingsDebugHeader)
            } footer: {
                Text(Strings.settingsDebugFooter)
            }
        }
    #endif

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
