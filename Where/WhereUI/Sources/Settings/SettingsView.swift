import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WhereCore

/// Settings tab: location permission + tracking, retroactive manual entry,
/// whole-database backup export/import, and the destructive "erase a year"
/// action.
struct SettingsView: View {
    @Environment(WhereModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var showClearConfirmation = false

    // Backup import: the picked file, the merge/replace choice, and the
    // success confirmation.
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showStrategyDialog = false
    @State private var showImportSuccess = false
    @State private var lastImportSummary: WhereController.ImportSummary?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                trackingSection
                remindersSection
                summarySection
                manualEntrySection
                backupSection
                dataSection
            }
            .navigationTitle(Strings.settingsTitle)
            .alert(Strings.settingsPermissionAlertTitle, isPresented: $model.permissionDenied) {
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
                ))
            }
            .alert(
                Strings.settingsBackupErrorTitle,
                isPresented: $model.isShowingBackupError,
                presenting: model.backupError,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var trackingSection: some View {
        @Bindable var model = model
        return Section {
            LocationStatusRow(status: model.authorizationStatus, isTracking: model.isTracking)

            Toggle(isOn: $model.trackingEnabled) {
                Label(Strings.settingsLocationToggle, systemImage: "location.fill")
            }

            if showGrantButton {
                Button {
                    Task { await model.requestPermission() }
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
        switch model.authorizationStatus {
            case .notDetermined, .whenInUse: true
            default: false
        }
    }

    /// Once access is denied/restricted (or stuck at When-In-Use), the only way
    /// forward is the Settings app.
    private var showOpenSettingsButton: Bool {
        switch model.authorizationStatus {
            case .denied, .restricted, .whenInUse: true
            default: false
        }
    }

    private var remindersSection: some View {
        @Bindable var model = model
        return Section {
            Toggle(isOn: $model.remindersEnabled) {
                Label(Strings.settingsRemindersToggle, systemImage: "bell.badge")
            }

            if model.remindersEnabled {
                DatePicker(
                    Strings.settingsReminderTime,
                    selection: $model.reminderTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !model.notificationsAuthorized {
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
        if model.remindersEnabled, !model.notificationsAuthorized {
            return Strings.settingsRemindersDeniedFooter
        }
        return Strings.settingsRemindersFooter
    }

    private var summarySection: some View {
        @Bindable var model = model
        return Section {
            Toggle(isOn: $model.summaryEnabled) {
                Label(Strings.settingsSummaryToggle, systemImage: "chart.bar.doc.horizontal")
            }

            if model.summaryEnabled {
                DatePicker(
                    Strings.settingsSummaryTime,
                    selection: $model.summaryTimeOfDay,
                    displayedComponents: .hourAndMinute,
                )

                if !model.notificationsAuthorized {
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
        if model.summaryEnabled, !model.notificationsAuthorized {
            return Strings.settingsSummaryDeniedFooter
        }
        return Strings.settingsSummaryFooter
    }

    private var manualEntrySection: some View {
        Section {
            NavigationLink {
                ManualDayEntryView()
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
            .disabled(model.backupState != .idle)

            Button {
                showImporter = true
            } label: {
                if model.backupState == .importing {
                    importProgressLabel
                } else {
                    Label(Strings.settingsBackupImport, systemImage: "square.and.arrow.down")
                }
            }
            .disabled(model.backupState != .idle)
        } header: {
            Text(Strings.settingsBackupHeader)
        } footer: {
            Text(Strings.settingsBackupFooter)
        }
    }

    /// Determinate progress for an in-flight import, driven by
    /// `model.backupProgress` as the controller writes each row.
    private var importProgressLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(Strings.settingsBackupImporting, systemImage: "square.and.arrow.down")
            ProgressView(value: model.backupProgress)
        }
    }

    /// Lazily-built backup for `ShareLink`. The closure runs only when the
    /// share sheet resolves the item; a failed export sets `model.backupError`
    /// (surfacing the alert) and throws to abort the share.
    private var backupArchiveFile: BackupArchiveFile {
        BackupArchiveFile { [model] in
            guard let url = await model.exportBackup() else {
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
                model.backupError = error.localizedDescription
        }
    }

    private func runImport(url: URL, strategy: WhereController.ImportStrategy) {
        Task {
            if let summary = await model.importBackup(from: url, strategy: strategy) {
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
                    Task { await model.clearSelectedYear() }
                }
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsDataConfirmMessage(year: model.selectedYear))
            }
        } header: {
            Text(Strings.settingsDataHeader)
        } footer: {
            Text(Strings.settingsDataFooter(year: model.selectedYear))
        }
    }

    private var eraseTitle: String {
        Strings.settingsDataErase(year: model.selectedYear)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .environment(PreviewSupport.loadedModel())
    }
#endif
