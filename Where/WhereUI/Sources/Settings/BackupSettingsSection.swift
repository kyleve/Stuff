import PeriscopeCore
import SFSafeSymbols
import SwiftUI
import WhereCore

/// The whole-database backup section embedded in ``DataSettingsView``.
/// Ordinary Settings structure stays native; branded preparation is presented
/// in its own composed-record sheet.
struct BackupSettingsSection: View {
    let backup: BackupModel

    @State private var showsPreparation = false

    var body: some View {
        backupSection
            .sheet(isPresented: $showsPreparation) {
                BackupPreparationView(backup: backup)
            }
    }

    private var backupSection: some View {
        Section {
            Button {
                backup.prepareExport()
                showsPreparation = true
            } label: {
                Label(
                    String(localized: .settingsBackupExport),
                    systemSymbol: .squareAndArrowUp,
                )
            }
            .disabled(isPreparing)
            .settingsRow(DataSettingsView.Item.exportBackup)
        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            Text(String(localized: .settingsBackupFooter))
        }
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }

    private var isPreparing: Bool {
        if case .preparing = backup.exportState { return true }
        return false
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
