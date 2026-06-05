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

    // Backup export: the built archive, presented in a share sheet, plus the
    // URL to clean up once that sheet is dismissed.
    @State private var exportedFile: ExportedFile?
    @State private var cleanupURL: URL?

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
            .sheet(item: $exportedFile, onDismiss: cleanupExportedFile) { file in
                ShareSheet(items: [file.url])
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
                isPresented: backupErrorBinding,
                presenting: model.backupError,
            ) { _ in
                Button(Strings.commonOK, role: .cancel) { model.backupError = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private var trackingSection: some View {
        Section {
            LocationStatusRow(status: model.authorizationStatus, isTracking: model.isTracking)

            Toggle(isOn: trackingBinding) {
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
            Button {
                Task {
                    if let url = await model.exportBackup() {
                        cleanupURL = url
                        exportedFile = ExportedFile(url: url)
                    }
                }
            } label: {
                if model.backupState == .exporting {
                    Label { Text(Strings.settingsBackupExporting) } icon: { ProgressView() }
                } else {
                    Label(Strings.settingsBackupExport, systemImage: "square.and.arrow.up")
                }
            }
            .disabled(model.backupState != .idle)

            Button {
                showImporter = true
            } label: {
                if model.backupState == .importing {
                    Label { Text(Strings.settingsBackupImporting) } icon: { ProgressView() }
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

    /// Bridges the model's optional `backupError` to the Bool an `.alert`
    /// presentation needs, clearing it when the alert is dismissed.
    private var backupErrorBinding: Binding<Bool> {
        Binding(
            get: { model.backupError != nil },
            set: { presented in if !presented { model.backupError = nil } },
        )
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

    private func cleanupExportedFile() {
        guard let url = cleanupURL else { return }
        // The archive lives in a unique temporary subdirectory; remove the
        // whole thing once the share sheet is gone.
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        cleanupURL = nil
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

    private var trackingBinding: Binding<Bool> {
        Binding(
            get: { model.isTracking },
            set: { isOn in
                Task {
                    if isOn {
                        await model.startTracking()
                    } else {
                        await model.stopTracking()
                    }
                }
            },
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// Identifiable wrapper so a freshly-built export URL can drive a
/// `.sheet(item:)` presentation.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin `UIActivityViewController` bridge so the exported `.zip` can be
/// emailed, AirDropped, or saved to Files via the system share sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

#if DEBUG
    #Preview {
        SettingsView()
            .environment(PreviewSupport.loadedModel())
    }
#endif
