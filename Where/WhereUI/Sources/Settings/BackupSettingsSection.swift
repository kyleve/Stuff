import PeriscopeCore
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``: export
/// to a shareable `.zip`, or import one by merging or replacing the store.
struct BackupSettingsSection: View {
    let backup: BackupModel

    /// Backup export: the ready-to-share archive built up-front, revealed as a
    /// `ShareLink` once the background export finishes.
    @State private var exportedArchiveURL: URL?

    // Backup import: the picked file and the merge/replace choice. The committed
    // result lives on `backup`, so its success/partial-success acknowledgment
    // survives this screen being popped mid-import.
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showStrategyDialog = false

    /// How long a finished export stays offered before it's auto-discarded.
    private static let exportRetention: Duration = .seconds(10 * 60)

    var body: some View {
        @Bindable var backup = backup
        backupSection
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
                importResultTitle,
                isPresented: $backup.isShowingImportResult,
                presenting: backup.lastImportResult,
            ) { result in
                if result.requiresCleanupRecovery {
                    Button(String(localized: .settingsBackupRetryCleanup)) {
                        runImportCleanupRecovery()
                    }
                }
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { result in
                Text(importResultMessage(result))
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
            // in-app "Exporting…" bar), then shared through a `ShareLink` to the
            // ready file — so the share sheet opens instantly instead of sitting
            // in the system's blocking "Preparing…" state.
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

            if backup.backupState == .idle, let url = exportedArchiveURL {
                ShareLink(
                    item: BackupArchiveFile(url: url),
                    preview: SharePreview(String(localized: .settingsBackupShareTitle)),
                ) {
                    Label(
                        String(localized: .settingsBackupShare),
                        systemImage: "square.and.arrow.up.on.square",
                    )
                }
            }

            if backup.importCleanupRecoverySummary != nil {
                Button {
                    runImportCleanupRecovery()
                } label: {
                    Label(
                        importCleanupActionTitle,
                        systemImage: "arrow.clockwise",
                    )
                }
                .disabled(backup.backupState != .idle)
            }

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
            .disabled(!backup.canImport)
            .settingsRow(DataSettingsView.Item.importBackup)
        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            if backup.importCleanupRecoverySummary != nil {
                Text(String(localized: .settingsBackupCleanupRequired))
            } else {
                Text(String(localized: .settingsBackupFooter))
            }
        }
        // A finished export lingers in the temp directory; stop offering it (and
        // reclaim the file) after a while so a stale link can't be shared. The
        // task restarts whenever `exportedArchiveURL` changes and no-ops while
        // it's `nil`.
        .task(id: exportedArchiveURL) {
            await expireExportIfNeeded()
        }
        .task {
            await backup.refreshImportRecoveryState()
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
                backup.presentBackupError(error)
        }
    }

    private func runImport(url: URL, strategy: BackupCoordinator.ImportStrategy) {
        Task {
            // A committed result drives either the success or partial-success
            // alert; the return value is unused here.
            _ = await backup.importBackup(from: url, strategy: strategy)
            pendingImportURL = nil
        }
    }

    private func runImportCleanupRecovery() {
        Task {
            await backup.retryImportCleanup()
        }
    }

    private var importCleanupActionTitle: String {
        if backup.backupState == .recoveringImportCleanup {
            String(localized: .settingsBackupRetryingCleanup)
        } else {
            String(localized: .settingsBackupRetryCleanup)
        }
    }

    private var importResultTitle: String {
        switch backup.lastImportResult {
            case .imported:
                String(localized: .settingsBackupImportedTitle)
            case .committedWithCleanupFailure:
                String(localized: .backupImportCleanupTitle)
            case nil:
                ""
        }
    }

    private func importResultMessage(_ result: BackupModel.ImportResult) -> String {
        switch result {
            case let .imported(summary):
                WhereFormat.settingsBackupImportedMessage(summary)
            case let .committedWithCleanupFailure(summary):
                WhereFormat.backupImportCleanupMessage(summary)
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
