import PeriscopeCore
import SFSafeSymbols
#if DEBUG
    import SnapshotKit
#endif
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WhereCore

/// Manual plaintext export plus encrypted automatic-backup controls, recovery
/// key, and the read-only catalog embedded in ``DataSettingsView``.
struct BackupSettingsSection: View {
    let backup: BackupModel
    let recordingEnabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedShareItem: BackupShareSheet.Item?

    var body: some View {
        @Bindable var backup = backup
        Group {
            manualExportSection
            automaticConfigurationSection
            recoveryKeySection
            automaticBackupsSection
        }
        .sheet(item: $presentedShareItem) { item in
            BackupShareSheet(item: item)
        }
        .alert(
            localized("settings.backup.errorTitle"),
            isPresented: $backup.isShowingBackupError,
            presenting: backup.backupError,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { message in
            Text(message)
        }
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
        .onDisappear { backup.hideRecoveryKey() }
    }

    private var manualExportSection: some View {
        Section {
            Button { runExport() } label: {
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
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }

    private var automaticConfigurationSection: some View {
        Section {
            Toggle(
                localized("settings.backup.automatic.enabled"),
                isOn: Binding(
                    get: { backup.automaticBackupsEnabled },
                    set: { value in
                        backup.setAutomaticBackupsEnabled(value)
                        Task { await backup.runIfDue(recordingEnabled: recordingEnabled) }
                    },
                ),
            )
            .disabled(!recordingEnabled)
            .settingsRow(DataSettingsView.Item.automaticBackups)

            Picker(
                localized("settings.backup.automatic.interval"),
                selection: Binding(
                    get: { backup.automaticBackupInterval },
                    set: {
                        backup.setAutomaticBackupInterval($0)
                        Task { await backup.runIfDue(recordingEnabled: recordingEnabled) }
                    },
                ),
            ) {
                ForEach(AutomaticBackupInterval.allCases, id: \.self) { interval in
                    Text(title(for: interval)).tag(interval)
                }
            }
            .disabled(!recordingEnabled || !backup.automaticBackupsEnabled)
            .settingsRow(DataSettingsView.Item.backupInterval)

            if !recordingEnabled {
                Label(
                    localized("settings.backup.automatic.unavailable"),
                    systemSymbol: .locationSlash,
                )
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(localized("settings.backup.automatic.header"))
        } footer: {
            Text(localized("settings.backup.automatic.footer"))
        }
    }

    private var recoveryKeySection: some View {
        Section {
            if let key = backup.revealedRecoveryKey {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(localized("settings.backup.recovery.value"))

                Button {
                    copyRecoveryKey(key)
                } label: {
                    Label(
                        localized("settings.backup.recovery.copy"),
                        systemSymbol: .docOnDoc,
                    )
                }
                .settingsRow(DataSettingsView.Item.copyRecoveryKey)

                Button {
                    backup.hideRecoveryKey()
                } label: {
                    Label(
                        localized("settings.backup.recovery.hide"),
                        systemSymbol: .eyeSlash,
                    )
                }
            } else {
                Button {
                    Task { await backup.revealRecoveryKey() }
                } label: {
                    Label(
                        localized("settings.backup.recovery.show"),
                        systemSymbol: .eye,
                    )
                }
                .settingsRow(DataSettingsView.Item.recoveryKey)
            }
        } header: {
            Text(localized("settings.backup.recovery.header"))
        } footer: {
            Text(localized("settings.backup.recovery.footer"))
        }
    }

    private var automaticBackupsSection: some View {
        Section {
            switch backup.catalogState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case let .loaded(catalog) where catalog.files.isEmpty:
                    Text(localized("settings.backup.list.empty"))
                        .foregroundStyle(.secondary)
                    if catalog.isICloudUnavailable {
                        iCloudUnavailableWarning
                    }
                case let .loaded(catalog):
                    ForEach(catalog.files) { file in
                        backupRow(file)
                    }
                    if catalog.isICloudUnavailable {
                        iCloudUnavailableWarning
                    }
                case let .failed(message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        Button(localized("settings.backup.list.retry")) {
                            Task { await backup.refreshCatalog() }
                        }
                    }
            }
        } header: {
            Text(localized("settings.backup.list.header"))
        }
    }

    private var iCloudUnavailableWarning: some View {
        Label(
            localized("settings.backup.list.icloudUnavailable"),
            systemSymbol: .exclamationmarkIcloud,
        )
        .foregroundStyle(.secondary)
    }

    private func backupRow(_ file: AutomaticBackupFile) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(size(for: file))
                Text(location(for: file.storageLocation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(file.exportedAt.formatted(date: .abbreviated, time: .shortened))
            } icon: {
                Image(systemSymbol: .lockFill)
                    .accessibilityLabel(localized("settings.backup.list.encrypted"))
            }
        }
    }

    private func size(for file: AutomaticBackupFile) -> String {
        guard let byteCount = file.byteCount else {
            return localized("settings.backup.list.sizeUnavailable")
        }
        return byteCount.formatted(ByteCountFormatStyle(style: .file))
    }

    private func location(for location: AutomaticBackupFile.StorageLocation) -> String {
        switch location {
            case .iCloudDrive: localized("settings.backup.location.icloud")
            case .appDocuments: localized("settings.backup.location.device")
        }
    }

    private func title(for interval: AutomaticBackupInterval) -> String {
        switch interval {
            case .daily: localized("settings.backup.interval.daily")
            case .weekly: localized("settings.backup.interval.weekly")
            case .monthly: localized("settings.backup.interval.monthly")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private func copyRecoveryKey(_ key: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: key]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(5 * 60),
            ],
        )
    }

    /// Determinate progress for an in-flight export, driven by
    /// `backup.backupProgress` as the backup coordinator makes progress.
    private func backupProgressLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemSymbol: systemSymbol)
            ProgressView(value: backup.backupProgress)
        }
    }

    private func runExport() {
        Task {
            if let url = await backup.exportBackup() {
                presentedShareItem = BackupShareSheet.Item(url: url)
            }
        }
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
                revealedKeySnapshot,
            ]
        }

        private static var revealedKeySnapshot: SnapshotCase {
            let model = PreviewSupport.backupModel()
            let prepare: @MainActor () -> Void = {
                model.configurePreview(
                    catalogState: .loaded(AutomaticBackupCatalog(
                        files: [],
                        isICloudUnavailable: false,
                    )),
                    recoveryKey: "VGhpcy1pcy1hLXNhbXBsZS1yZWNvdmVyeS1rZXku",
                )
            }
            prepare()
            return whereSnapshot(
                name: "RevealedKey",
                configurations: .fullContentPhoneLightDark,
                // Rehosting invokes the production disappearance handler.
                // Seed the revealed fixture before both sizing and capture.
                onReadyToMeasure: prepare,
                onReadyToSnapshot: prepare,
            ) {
                snapshotForm(model: model, recordingEnabled: true)
            }
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
        ) -> some View {
            let model = PreviewSupport.backupModel()
            model.configurePreview(
                catalogState: .loaded(catalog),
                recoveryKey: nil,
            )
            return snapshotForm(model: model, recordingEnabled: recordingEnabled)
        }

        private static func snapshotForm(model: BackupModel, recordingEnabled: Bool) -> some View {
            NavigationStack {
                Form {
                    BackupSettingsSection(
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
