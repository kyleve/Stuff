import LifecycleKit
import LogViewerUI
import StuffCore
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
    // Most settings live on the logged-in session; `model` is kept only to
    // drive the reset sequence (which rebuilds the session from scratch).
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

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                trackingSection
                remindersSection
                summarySection
                appIconSection
                manualEntrySection
                backupSection
                dataSection
                resetSection
                #if DEBUG
                    developerSection
                #endif
            }
            .navigationTitle(.settings.title)
            .sheet(isPresented: $showAppIcon) {
                AppIconView()
            }
            .alert(
                LocalizedStrings.Settings.PermissionAlert.title.localized,
                isPresented: $session.permissionDenied,
            ) {
                Button(LocalizedStrings.Settings.PermissionAlert.openSettings.localized) {
                    openSystemSettings()
                }
                Button(
                    LocalizedStrings.Settings.PermissionAlert.notNow.localized,
                    role: .cancel,
                ) {}
            } message: {
                Text(localized: .settings.permissionAlert.message)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.zip],
                onCompletion: handleImportSelection,
            )
            .confirmationDialog(
                LocalizedStrings.Settings.Backup.importStrategyTitle.localized,
                isPresented: $showStrategyDialog,
                titleVisibility: .visible,
                presenting: pendingImportURL,
            ) { url in
                Button(LocalizedStrings.Settings.Backup.merge.localized) { runImport(
                    url: url,
                    strategy: .merge,
                ) }
                Button(LocalizedStrings.Settings.Backup.replace.localized, role: .destructive) {
                    runImport(url: url, strategy: .replace)
                }
                Button(LocalizedStrings.Settings.Data.cancel.localized, role: .cancel) {
                    pendingImportURL = nil
                }
            } message: { _ in
                Text(localized: .settings.backup.importStrategyMessage)
            }
            .alert(
                LocalizedStrings.Settings.Backup.importedTitle.localized,
                isPresented: $showImportSuccess,
                presenting: lastImportSummary,
            ) { _ in
                Button(LocalizedStrings.Common.ok.localized, role: .cancel) {}
            } message: { summary in
                Text(localized: .settings.backup.importedMessage(
                    samples: summary.sampleCount,
                    evidence: summary.evidenceCount,
                    manualDays: summary.manualDayCount,
                ))
            }
            .alert(
                LocalizedStrings.Settings.Backup.errorTitle.localized,
                isPresented: $session.isShowingBackupError,
                presenting: session.backupError,
            ) { _ in
                Button(LocalizedStrings.Common.ok.localized, role: .cancel) {}
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
                Label(
                    LocalizedStrings.Settings.Location.toggle.localized,
                    systemImage: "location.fill",
                )
            }

            if showGrantButton {
                Button {
                    Task { await session.requestPermission() }
                } label: {
                    Label(
                        LocalizedStrings.Settings.Location.grant.localized,
                        systemImage: "location.magnifyingglass",
                    )
                }
            }

            if showOpenSettingsButton {
                Button {
                    openSystemSettings()
                } label: {
                    Label(
                        LocalizedStrings.Settings.PermissionAlert.openSettings.localized,
                        systemImage: "gear",
                    )
                }
            }
        } header: {
            Text(localized: .settings.location.header)
        } footer: {
            Text(localized: .settings.location.footer)
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
        @Bindable var session = session
        return Section {
            Toggle(isOn: $session.remindersEnabled) {
                Label(
                    LocalizedStrings.Settings.Reminders.toggle.localized,
                    systemImage: "bell.badge",
                )
            }

            if session.remindersEnabled {
                DatePicker(
                    LocalizedStrings.Settings.Reminders.time.localized,
                    selection: $session.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !session.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(
                            LocalizedStrings.Settings.Reminders.openSettings.localized,
                            systemImage: "bell.slash",
                        )
                    }
                }
            }
        } header: {
            Text(localized: .settings.reminders.header)
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if session.remindersEnabled, !session.notificationsAuthorized {
            return LocalizedStrings.Settings.Reminders.deniedFooter.localized
        }
        return LocalizedStrings.Settings.Reminders.footer.localized
    }

    private var summarySection: some View {
        @Bindable var session = session
        return Section {
            Toggle(isOn: $session.summaryEnabled) {
                Label(
                    LocalizedStrings.Settings.Summary.toggle.localized,
                    systemImage: "chart.bar.doc.horizontal",
                )
            }

            if session.summaryEnabled {
                DatePicker(
                    LocalizedStrings.Settings.Summary.time.localized,
                    selection: $session.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !session.notificationsAuthorized {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label(
                            LocalizedStrings.Settings.Reminders.openSettings.localized,
                            systemImage: "bell.slash",
                        )
                    }
                }
            }
        } header: {
            Text(localized: .settings.summary.header)
        } footer: {
            Text(summaryFooter)
        }
    }

    private var summaryFooter: String {
        if session.summaryEnabled, !session.notificationsAuthorized {
            return LocalizedStrings.Settings.Summary.deniedFooter.localized
        }
        return LocalizedStrings.Settings.Summary.footer.localized
    }

    private var appIconSection: some View {
        Section {
            Button {
                showAppIcon = true
            } label: {
                Label(LocalizedStrings.Settings.AppIcon.link.localized, systemImage: "app.badge")
            }
        } header: {
            Text(localized: .settings.appIcon.header)
        } footer: {
            Text(localized: .settings.appIcon.footer)
        }
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView()
            } label: {
                Label(
                    LocalizedStrings.Settings.Manual.link.localized,
                    systemImage: "calendar.badge.plus",
                )
            }
        } header: {
            Text(localized: .settings.manual.header)
        } footer: {
            Text(localized: .settings.manual.footer)
        }
    }

    private var backupSection: some View {
        Section {
            // `ShareLink` builds the archive lazily through `BackupArchiveFile`
            // and presents the native share sheet (with its own export
            // progress), so no custom `UIActivityViewController` is needed.
            ShareLink(
                item: backupArchiveFile,
                preview: SharePreview(LocalizedStrings.Settings.Backup.shareTitle.localized),
            ) {
                Label(
                    LocalizedStrings.Settings.Backup.export.localized,
                    systemImage: "square.and.arrow.up",
                )
            }
            .disabled(session.backupState != .idle)

            Button {
                showImporter = true
            } label: {
                if session.backupState == .importing {
                    importProgressLabel
                } else {
                    Label(
                        LocalizedStrings.Settings.Backup.importData.localized,
                        systemImage: "square.and.arrow.down",
                    )
                }
            }
            .disabled(session.backupState != .idle)
        } header: {
            Text(localized: .settings.backup.header)
        } footer: {
            Text(localized: .settings.backup.footer)
        }
    }

    /// Determinate progress for an in-flight import, driven by
    /// `session.backupProgress` as the backup coordinator writes each row.
    private var importProgressLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                LocalizedStrings.Settings.Backup.importing.localized,
                systemImage: "square.and.arrow.down",
            )
            ProgressView(value: session.backupProgress)
        }
    }

    /// Lazily-built backup for `ShareLink`. The closure runs only when the
    /// share sheet resolves the item; a failed export sets `session.backupError`
    /// (surfacing the alert) and throws to abort the share.
    private var backupArchiveFile: BackupArchiveFile {
        BackupArchiveFile { [session] in
            guard let url = await session.exportBackup() else {
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
                session.backupError = error.localizedDescription
        }
    }

    private func runImport(url: URL, strategy: BackupCoordinator.ImportStrategy) {
        Task {
            if let summary = await session.importBackup(from: url, strategy: strategy) {
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
                    Task { await session.clearSelectedYear() }
                }
                Button(LocalizedStrings.Settings.Data.cancel.localized, role: .cancel) {}
            } message: {
                Text(localized: .settings.data.confirmMessage(year: session.selectedYear))
            }
        } header: {
            Text(localized: .settings.data.header)
        } footer: {
            Text(localized: .settings.data.footer(year: session.selectedYear))
        }
    }

    private var eraseTitle: String {
        LocalizedStrings.Settings.Data.erase(year: session.selectedYear).localized
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
                Label(
                    LocalizedStrings.Settings.Reset.erase.localized,
                    systemImage: "arrow.counterclockwise",
                )
            }
            .confirmationDialog(
                LocalizedStrings.Settings.Reset.erase.localized,
                isPresented: $showResetConfirmation,
                titleVisibility: .visible,
            ) {
                Button(LocalizedStrings.Settings.Reset.confirm.localized, role: .destructive) {
                    requestReset()
                }
                Button(LocalizedStrings.Settings.Data.cancel.localized, role: .cancel) {}
            } message: {
                Text(localized: .settings.reset.message)
            }
        } footer: {
            Text(localized: .settings.reset.footer)
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
                        title: LocalizedStrings.Settings.Debug.logsTitle.localized,
                    ))
                } label: {
                    Label(
                        LocalizedStrings.Settings.Debug.logsLink.localized,
                        systemImage: "ladybug",
                    )
                }

                if let configuration = session.swiftDataInspectorConfiguration {
                    NavigationLink {
                        SwiftDataInspectorView(configuration: configuration)
                    } label: {
                        Label(
                            LocalizedStrings.Settings.Debug.inspectorLink.localized,
                            systemImage: "cylinder.split.1x2",
                        )
                    }
                }
            } header: {
                Text(localized: .settings.debug.header)
            } footer: {
                Text(localized: .settings.debug.footer)
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
        SettingsView()
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }
#endif
