import PeriscopeCore
import SFSafeSymbols
import SwiftUI
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``.
/// Imports deliberately live only in onboarding, where the app can recover a
/// committed archive before exposing a running session.
struct BackupSettingsSection: View {
    let backup: BackupModel

    /// Backup export: the ready-to-share archive built up-front, presented as
    /// soon as the background export finishes.
    @State private var presentedShareItem: BackupShareSheet.Item?

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
                        systemSymbol: .squareAndArrowUp,
                    )
                } else {
                    Label(
                        String(localized: .settingsBackupExport),
                        systemSymbol: .squareAndArrowUp,
                    )
                }
            }
            .disabled(backup.backupState != .idle)
            .settingsRow(DataSettingsView.Item.exportBackup)
        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            Text(String(localized: .settingsBackupFooter))
        }
        // Log View Mode: reveal an inspect badge for backup export
        // events on this section. A no-op in release.
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }

    /// Determinate progress for an in-flight export, driven by
    /// `backup.backupProgress` as the backup coordinator makes progress.
    private func backupProgressLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemSymbol: systemSymbol)
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
}

#if DEBUG
    #Preview {
        Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel())
        }
        .whereBroadwayRoot()
    }
#endif
