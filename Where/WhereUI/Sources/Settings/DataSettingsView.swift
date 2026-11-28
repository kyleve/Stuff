import LifecycleKitUI
import PeriscopeCore
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings drill-in for Where's privacy promise and data management: export
/// the database, erase the selected year's data, or reset the entire app.
struct DataSettingsDestination: View {
    let report: YearReportModel
    var focus: SettingsFocus?

    var body: some View {
        ObservableHostingView {
            BackupModel(services: report.services)
        } content: { backup in
            DataSettingsView(report: report, backup: backup, focus: focus)
        }
    }
}

struct DataSettingsView: View {
    let report: YearReportModel
    let backup: BackupModel
    var focus: SettingsFocus?

    @Environment(WhereModel.self) private var model
    // The reset plan is rooted at the session being torn down, so this screen
    // reads it from the environment (it only renders at `.ready`, where the
    // session is present) rather than the teardown re-reading an optional.
    @Environment(WhereSession.self) private var session
    @Environment(\.lifecycle) private var lifecycle

    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false
    @State private var presentedShareItem: BackupShareSheet.Item?
    @State private var exportRequest: UUID?

    var body: some View {
        @Bindable var backup = backup
        SettingsFocusScope(focus: focus) {
            Form {
                DataPrivacyPassport(presentation: PrivacyPassportPresentation(
                    configuration: model.diagnosticReporting.effectiveConfiguration,
                ))
                BackupSettingsSection(backup: backup, onExport: requestExport)
                EraseYearSection(
                    year: report.selectedYear,
                    showsConfirmation: $showClearConfirmation,
                    erase: { Task { await report.clearSelectedYear() } },
                )
                ResetAppSection(showsConfirmation: $showResetConfirmation, reset: requestReset)
            }
            .whereFormRoot()
        }
        .navigationTitle(String(localized: .settingsDataHeader))
        .navigationBarTitleDisplayMode(.inline)
        // Keep one presenter outside the Form's reusable section content.
        // The export row changes from progress to idle as the archive arrives.
        .sheet(item: $presentedShareItem, content: BackupShareSheet.init)
        .alert(
            String(localized: .settingsBackupErrorTitle),
            isPresented: $backup.isShowingBackupError,
            presenting: backup.backupError,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .task(id: exportRequest) {
            guard let request = exportRequest else { return }
            let archive = await backup.exportBackup()
            guard !Task.isCancelled, exportRequest == request else { return }
            if let archive {
                presentedShareItem = BackupShareSheet.Item(url: archive)
            }
            exportRequest = nil
        }
        .onDisappear { exportRequest = nil }
    }

    private func requestExport() {
        guard exportRequest == nil else { return }
        exportRequest = UUID()
    }

    // Whole-app teardown: wipes every year's data and returns to first-run
    // onboarding, run through the `LifecycleProxy` that `LifecycleContainer`
    // publishes under `\.lifecycle`. The proxy asserts in debug / no-ops in
    // release when no container is above (e.g. previews).

    private func requestReset() {
        Task { await lifecycle.teardown(WhereLaunch.resetPlan(for: model), input: session) }
    }
}

extension DataSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .data
    }

    enum Item: SettingsItem {
        case exportBackup
        case eraseYear
        case resetApp

        var title: String {
            switch self {
                case .exportBackup: String(localized: .settingsBackupExport)
                case .eraseYear: String(localized: .settingsEraseYearTitle)
                case .resetApp: String(localized: .settingsResetErase)
            }
        }

        var keywords: [String] {
            switch self {
                case .exportBackup: splitKeywords(String(localized: .settingsKeywordsExport))
                case .eraseYear: splitKeywords(String(localized: .settingsKeywordsEraseYear))
                case .resetApp: splitKeywords(String(localized: .settingsKeywordsReset))
            }
        }
    }
}

private struct EraseYearSection: View {
    let year: Int
    @Binding var showsConfirmation: Bool
    let erase: () -> Void

    var body: some View {
        Section {
            EraseYearButton(year: year, showsConfirmation: $showsConfirmation, erase: erase)
        } header: {
            Text(String(localized: .settingsDataHeader))
        } footer: {
            Text(WhereFormat.settingsDataFooter(year: year))
        }
    }
}

private struct EraseYearButton: View {
    let year: Int
    @Binding var showsConfirmation: Bool
    let erase: () -> Void

    var body: some View {
        let eraseTitle = WhereFormat.settingsDataErase(year: year)
        Button(role: .destructive) {
            showsConfirmation = true
        } label: {
            Label(eraseTitle, systemSymbol: .trash)
        }
        .settingsRow(DataSettingsView.Item.eraseYear)
        .confirmationDialog(
            eraseTitle,
            isPresented: $showsConfirmation,
            titleVisibility: .visible,
        ) {
            Button(eraseTitle, role: .destructive) {
                erase()
            }
            Button(String(localized: .settingsDataCancel), role: .cancel) {}
        } message: {
            Text(WhereFormat.settingsDataConfirmMessage(year: year))
        }
    }
}

private struct ResetAppSection: View {
    @Binding var showsConfirmation: Bool
    let reset: () -> Void

    var body: some View {
        Section {
            ResetAppButton(showsConfirmation: $showsConfirmation, reset: reset)
        } footer: {
            Text(String(localized: .settingsResetFooter))
        }
    }
}

private struct ResetAppButton: View {
    @Binding var showsConfirmation: Bool
    let reset: () -> Void

    var body: some View {
        Button(role: .destructive) {
            showsConfirmation = true
        } label: {
            Label(String(localized: .settingsResetErase), systemSymbol: .arrowCounterclockwise)
        }
        .settingsRow(DataSettingsView.Item.resetApp)
        .confirmationDialog(
            String(localized: .settingsResetErase),
            isPresented: $showsConfirmation,
            titleVisibility: .visible,
        ) {
            Button(String(localized: .settingsResetConfirm), role: .destructive) {
                reset()
            }
            Button(String(localized: .settingsDataCancel), role: .cancel) {}
        } message: {
            Text(String(localized: .settingsResetMessage))
        }
    }
}

private struct DataPrivacyPassport: View {
    let presentation: PrivacyPassportPresentation

    var body: some View {
        PrivacyPassportCard(presentation: presentation, disclosureInteraction: .linkToSettings)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}

#if DEBUG
    extension DataSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                ],
            ) {
                DataSettingsSnapshot()
            }
        }
    }

    private struct DataSettingsSnapshot: View {
        var body: some View {
            NavigationStack {
                DataSettingsView(
                    report: PreviewSupport.loadedYearReportModel(),
                    backup: PreviewSupport.backupModel(),
                )
                .environment(PreviewSupport.loadedModel())
                .environment(PreviewSupport.loadedSession())
            }
        }
    }

    #Preview {
        DataSettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension DataSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            DataSettingsView.self,
            title: "Data",
        ) { world in
            DataSettingsDestination(report: world.report)
        }
    }
#endif

/// The whole-database backup section embedded in ``DataSettingsView``.
/// Imports deliberately live only in onboarding, where the app can recover a
/// committed archive before exposing a running session.
private struct BackupSettingsSection: View {
    let backup: BackupModel
    let onExport: () -> Void

    var body: some View {
        Section {
            // The archive is built up-front on a background task (with an
            // in-app "Exporting…" bar), then handed to the system activity sheet
            // as a ready file — so it opens instantly instead of sitting in the
            // system's blocking "Preparing…" state.
            BackupExportButton(backup: backup, onExport: onExport)
        } header: {
            Text(String(localized: .settingsBackupHeader))
        } footer: {
            Text(String(localized: .settingsBackupFooter))
        }
        // Log View Mode: reveal an inspect badge for backup export
        // events on this section. A no-op in release.
        .debugLogInspectable(WhereLog.session(BackupModelLog.self))
    }
}

private struct BackupExportButton: View {
    let backup: BackupModel
    let onExport: () -> Void

    var body: some View {
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
    }

    /// The backup coordinator reports completion as the archive is generated.
    private func backupProgressLabel(_ title: String, systemSymbol: SFSymbol) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemSymbol: systemSymbol)
            ProgressView(value: backup.backupProgress)
        }
    }
}

#if DEBUG
    #Preview("Backup section") {
        Form {
            BackupSettingsSection(backup: PreviewSupport.backupModel(), onExport: {})
        }
        .whereBroadwayRoot()
    }
#endif
