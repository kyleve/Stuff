import PeriscopeCore
import SwiftUI
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``.
/// Imports deliberately live only in onboarding, where the app can recover a
/// committed archive before exposing a running session.
struct BackupSettingsSection: View {
    let backup: BackupModel

    /// Backup export: the ready-to-share archive built up-front, revealed as a
    /// second row once the background export finishes.
    @State private var exportedArchiveURL: URL?
    @State private var presentedShareItem: BackupShareSheet.Item?

    /// How long a finished export stays offered before it's auto-discarded.
    private static let exportRetention: Duration = .seconds(10 * 60)

    var body: some View {
        @Bindable var backup = backup
        backupSection
            .sheet(item: $presentedShareItem) { item in
                BackupShareSheet(item: item)
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

            if backup.backupState == .idle, let url = exportedArchiveURL {
                Button {
                    presentedShareItem = BackupShareSheet.Item(url: url)
                } label: {
                    Label(
                        String(localized: .settingsBackupShare),
                        systemImage: "square.and.arrow.up.on.square",
                    )
                }
            }

        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            Text(String(localized: .settingsBackupFooter))
        }
        // A finished export lingers in the temp directory; stop offering it (and
        // reclaim the file) after a while so a stale link can't be shared. The
        // task restarts whenever `exportedArchiveURL` changes and no-ops while
        // it's `nil`.
        .task(id: exportedArchiveURL) {
            await expireExportIfNeeded()
        }
        // Log View Mode: reveal an inspect badge for backup export
        // events on this section. A no-op in release.
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }

    /// Determinate progress for an in-flight export, driven by
    /// `backup.backupProgress` as the backup coordinator makes progress.
    private func backupProgressLabel(_ title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
            ProgressView(value: backup.backupProgress)
        }
    }

    /// Build the archive in the background, then reveal the share row. Clearing
    /// `exportedArchiveURL` first hides the stale share row — the coordinator
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
}

#if DEBUG
    #Preview {
        Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel())
        }
        .whereBroadwayRoot()
    }
#endif
