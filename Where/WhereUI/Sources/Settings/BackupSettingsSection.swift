import PeriscopeCore
#if DEBUG
    import SnapshotKit
#endif
import SwiftUI
import WhereCore

/// Owns the Data page's automatic-backup observations and recovery-key lifetime.
struct BackupSettingsSection: View {
    let backup: BackupModel
    let recordingEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        BackupSettingsContent(backup: backup, recordingEnabled: recordingEnabled)
            .task(id: recordingEnabled) {
                await backup.activate(recordingEnabled: recordingEnabled)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                    case .active:
                        Task { await backup.activate(recordingEnabled: recordingEnabled) }
                    case .inactive, .background:
                        backup.hideRecoveryKey()
                    @unknown default:
                        backup.hideRecoveryKey()
                }
            }
            .onDisappear { backup.deactivate() }
    }
}

#if DEBUG
    extension BackupSettingsSection: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(
                    name: "RecordingDisabled",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    snapshotForm(recordingEnabled: false)
                },
                whereSnapshot(
                    name: "NoBackups",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    snapshotForm(recordingEnabled: true)
                },
                whereSnapshot(
                    name: "Populated",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    snapshotForm(
                        recordingEnabled: true,
                        catalog: AutomaticBackupCatalog(
                            files: snapshotFiles,
                            isICloudUnavailable: false,
                        ),
                    )
                },
                whereSnapshot(
                    name: "PartialICloudFailure",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    snapshotForm(
                        recordingEnabled: true,
                        catalog: AutomaticBackupCatalog(
                            files: [],
                            isICloudUnavailable: true,
                        ),
                    )
                },
                whereSnapshot(
                    name: "RevealedKey",
                    configurations: .fullContentPhoneLightDark,
                ) {
                    snapshotForm(
                        recordingEnabled: true,
                        recoveryKey: "VGhpcy1pcy1hLXNhbXBsZS1yZWNvdmVyeS1rZXku",
                    )
                },
            ]
        }

        private static var snapshotFiles: [AutomaticBackupFile] {
            [
                AutomaticBackupFile(
                    url: URL(fileURLWithPath: "/backup/newest.wherebackup"),
                    exportedAt: PreviewSupport.referenceNow,
                    byteCount: 2_450_000,
                    storageLocation: .iCloudDrive,
                    protection: .aesGCM256,
                ),
                AutomaticBackupFile(
                    url: URL(fileURLWithPath: "/backup/older.wherebackup"),
                    exportedAt: PreviewSupport.referenceNow.addingTimeInterval(-7 * 24 * 60 * 60),
                    byteCount: nil,
                    storageLocation: .appDocuments,
                    protection: .aesGCM256,
                ),
            ]
        }

        private static func snapshotForm(
            recordingEnabled: Bool,
            catalog: AutomaticBackupCatalog = AutomaticBackupCatalog(
                files: [],
                isICloudUnavailable: false,
            ),
            recoveryKey: String? = nil,
        ) -> some View {
            let model = PreviewSupport.backupModel()
            model.configurePreview(
                catalogState: .loaded(catalog),
                recoveryKey: recoveryKey,
            )
            return snapshotForm(model: model, recordingEnabled: recordingEnabled)
        }

        private static func snapshotForm(model: BackupModel, recordingEnabled: Bool) -> some View {
            NavigationStack {
                Form {
                    BackupSettingsContent(
                        backup: model,
                        recordingEnabled: recordingEnabled,
                    )
                }
                .navigationTitle("Data")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    #Preview {
        Form {
            BackupSettingsSection(
                backup: PreviewSupport.backupModel(),
                recordingEnabled: true,
            )
        }
        .whereBroadwayRoot()
    }
#endif
