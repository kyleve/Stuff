import PeriscopeCore
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``: export
/// to a shareable `.zip`, or import one by merging or replacing the store.
struct BackupSettingsSection: View {
    let backup: BackupModel

    /// Backup export: the ready-to-share archive built up-front, presented as
    /// soon as the background export finishes.
    @State private var presentedShareItem: BackupShareSheet.Item?

    // Backup import: the picked file and the merge/replace choice. The success
    // confirmation lives on `backup` (the model), so it survives this screen
    // being popped mid-import.
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showStrategyDialog = false

    var body: some View {
        @Bindable var backup = backup
        backupSection
            .sheet(item: $presentedShareItem) { item in
                BackupShareSheet(item: item)
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
                Button(String(localized: .settingsBackupMerge)) { runImport(
                    url: url,
                    strategy: .merge,
                )
                }
                Button(String(localized: .settingsBackupReplace), role: .destructive) {
                    runImport(url: url, strategy: .replace)
                }
                Button(String(localized: .settingsDataCancel), role: .cancel) {
                    pendingImportURL = nil
                }
            } message: { _ in
                Text(String(localized: .settingsBackupImportStrategyMessage))
            }
            .alert(
                String(localized: .settingsBackupImportedTitle),
                isPresented: $backup.isShowingImportSuccess,
                presenting: backup.lastImportSummary,
            ) { _ in
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { summary in
                Text(WhereFormat.settingsBackupImportedMessage(
                    samples: summary.sampleCount,
                    evidence: summary.evidenceCount,
                    manualDays: summary.manualDayCount,
                    dismissedIssues: summary.dismissedIssueCount,
                    trackedRegions: summary.trackedRegionCount,
                ))
            }
            .alert(
                String(localized: .settingsBackupErrorTitle),
                isPresented: $backup.isShowingBackupError,
                presenting: backup.backupError,
            ) { _ in
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    private var backupSection: some View {
        Section {
            // The archive is built up-front on a background task (with an
            // in-app "Exporting…" bar), then handed to the system activity sheet
            // as a ready file — so it opens instantly instead of sitting in the
            // system's blocking "Preparing…" state.
            Button {
                runExport()
            } label: {
                if backup.backupState == .exporting {
                    backupProgressLabel(
                        String(localized: .settingsBackupExporting),
                        systemImage: "square.and.arrow.up",
                    )
                } else {
                    Label(
                        String(localized: .settingsBackupExport),
                        systemImage: "square.and.arrow.up",
                    )
                }
            }
            .disabled(backup.backupState != .idle)
            .settingsRow(DataSettingsView.Item.exportBackup)

            Button {
                showImporter = true
            } label: {
                if backup.backupState == .importing {
                    backupProgressLabel(
                        String(localized: .settingsBackupImporting),
                        systemImage: "square.and.arrow.down",
                    )
                } else {
                    Label(
                        String(localized: .settingsBackupImport),
                        systemImage: "square.and.arrow.down",
                    )
                }
            }
            .disabled(backup.backupState != .idle)
            .settingsRow(DataSettingsView.Item.importBackup)
        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            Text(String(localized: .settingsBackupFooter))
        }
        // Log View Mode: reveal an inspect badge for backup export/import
        // events on this section. A no-op in release.
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }

    /// Determinate progress for an in-flight export or import, driven by
    /// `backup.backupProgress` as the backup coordinator makes progress.
    private func backupProgressLabel(_ title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
            ProgressView(value: backup.backupProgress)
        }
    }

    /// Build the archive in the background, then present its system activity
    /// sheet. The coordinator purges the previous export when this one starts.
    private func runExport() {
        Task {
            if let url = await backup.exportBackup() {
                presentedShareItem = BackupShareSheet.Item(url: url)
            }
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
            // On success `backup` sets `lastImportSummary`, which drives the
            // confirmation alert; the return value is unused here.
            _ = await backup.importBackup(from: url, strategy: strategy)
            pendingImportURL = nil
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel())
        }
        .whereBroadwayRoot()
    }
#endif
