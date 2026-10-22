import PeriscopeCore
import SFSafeSymbols
import SwiftUI
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``.
/// Imports deliberately live only in onboarding, where the app can recover a
/// committed archive before exposing a running session.
struct BackupSettingsSection: View {
    let backup: BackupModel
    let onExport: () -> Void

    var body: some View {
        Section {
            // The archive is built up-front on a background task (with an
            // in-app "Exporting…" bar), then handed to the system activity sheet
            // as a ready file — so it opens instantly instead of sitting in the
            // system's blocking "Preparing…" state.
            Button(action: onExport) {
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
}

#if DEBUG
    #Preview {
        Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel(), onExport: {})
        }
        .whereBroadwayRoot()
    }
#endif
