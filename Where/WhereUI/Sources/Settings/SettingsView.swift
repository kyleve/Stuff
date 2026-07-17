import LifecycleKit
import SnapshotKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WhereCore

/// Settings tab: location permission + tracking, notification reminders and
/// summaries, the report year, whole-database backup export/import, and the
/// destructive "erase a year" action. (Logging or overriding a day moved to the
/// Primary tab's "Logged days" toolbar item.)
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
    /// Snapshot captures substitute the compact time pickers' value capsules
    /// with a deterministic stand-in — the live capsule's rendering depends on
    /// real-world clock state (see `SnapshotDatePickerStandIn`).
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showAppIcon = false

    // "Find issues now": a manual, force-past-the-throttle data-issue scan and
    // its result (issue count) shown until the next scan.
    @State private var isScanningForIssues = false
    @State private var lastScanIssueCount: Int?

    /// Backup export: the ready-to-share archive built up-front, revealed as a
    /// `ShareLink` once the background export finishes.
    @State private var exportedArchiveURL: URL?

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
                yearSection
                appIconSection
                backupSection
                dataSection
                resetSection
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
                    trackedRegions: summary.trackedRegionCount,
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
                if isCapturingSnapshot {
                    SnapshotDatePickerStandIn(
                        title: Strings.settingsReminderTime,
                        selection: .timeOfDay(reminders.reminderTimeOfDay),
                    )
                } else {
                    DatePicker(
                        Strings.settingsReminderTime,
                        selection: $reminders.reminderTimeOfDay,
                        displayedComponents: .hourAndMinute,
                    )
                }

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
                if isCapturingSnapshot {
                    SnapshotDatePickerStandIn(
                        title: Strings.settingsSummaryTime,
                        selection: .timeOfDay(reminders.summaryTimeOfDay),
                    )
                } else {
                    DatePicker(
                        Strings.settingsSummaryTime,
                        selection: $reminders.summaryTimeOfDay,
                        displayedComponents: .hourAndMinute,
                    )
                }

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

    private var tabsSection: some View {
        @Bindable var report = report
        return Section {
            Toggle(isOn: $report.hideEmptyTabs) {
                Label(Strings.settingsTabsToggle, systemImage: "rectangle.bottomthird.inset.filled")
            }
        } header: {
            Text(Strings.settingsTabsHeader)
        } footer: {
            Text(Strings.settingsTabsFooter)
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

    /// The report year moved here off the Primary/Elsewhere toolbars — it's set
    /// rarely, so it lives in Settings rather than taking a permanent toolbar
    /// slot. Reuses `YearSelector`, which reads/drives the shared scene model, so
    /// changing it here updates every tab (and the erase-year row below).
    private var yearSection: some View {
        Section {
            LabeledContent(Strings.settingsYearLabel) {
                YearSelector(report: report)
            }
        } header: {
            Text(Strings.settingsYearHeader)
        } footer: {
            Text(Strings.settingsYearFooter)
        }
    }

    private var backupSection: some View {
        Section {
            // The archive is built up-front on a background task (with an
            // in-app "Exporting…" bar), then shared through a `ShareLink` to the
            // ready file — so the share sheet opens instantly instead of sitting
            // in the system's blocking "Preparing…" state.
            Button {
                runExport()
            } label: {
                if backup.backupState == .exporting {
                    backupProgressLabel(
                        Strings.settingsBackupExporting,
                        systemImage: "square.and.arrow.up",
                    )
                } else {
                    Label(Strings.settingsBackupExport, systemImage: "square.and.arrow.up")
                }
            }
            .disabled(backup.backupState != .idle)

            if backup.backupState == .idle, let url = exportedArchiveURL {
                ShareLink(
                    item: BackupArchiveFile(url: url),
                    preview: SharePreview(Strings.settingsBackupShareTitle),
                ) {
                    Label(Strings.settingsBackupShare, systemImage: "square.and.arrow.up.on.square")
                }
            }

            Button {
                showImporter = true
            } label: {
                if backup.backupState == .importing {
                    backupProgressLabel(
                        Strings.settingsBackupImporting,
                        systemImage: "square.and.arrow.down",
                    )
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
        // A finished export lingers in the temp directory; stop offering it (and
        // reclaim the file) after a while so a stale link can't be shared. The
        // task restarts whenever `exportedArchiveURL` changes and no-ops while
        // it's `nil`.
        .task(id: exportedArchiveURL) {
            await expireExportIfNeeded()
        }
    }

    /// Determinate progress for an in-flight export or import, driven by
    /// `backup.backupProgress` as the backup coordinator makes progress.
    private func backupProgressLabel(_ title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
            ProgressView(value: backup.backupProgress)
        }
    }

    /// How long a finished export stays offered before it's auto-discarded.
    private static let exportRetention: Duration = .seconds(10 * 60)

    /// Build the archive in the background, then reveal the share row. Clearing
    /// `exportedArchiveURL` first hides the stale share link — the coordinator
    /// purges the previous export's directory when this new export starts.
    private func runExport() {
        exportedArchiveURL = nil
        Task {
            if let url = await backup.exportBackup() {
                exportedArchiveURL = url
            }
        }
    }

    /// After a finished export has been offered for `exportRetention`, hide the
    /// share row and delete the temp file. Hiding before the delete closes the
    /// window where the row could point at an already-removed file. A no-op when
    /// there's no export to expire (the `.task(id:)` also runs on `nil`).
    private func expireExportIfNeeded() async {
        guard exportedArchiveURL != nil else { return }
        try? await Task.sleep(for: Self.exportRetention)
        guard !Task.isCancelled else { return }
        exportedArchiveURL = nil
        await backup.discardExport()
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
