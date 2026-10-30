import LifecycleKitUI
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings drill-in for Where's privacy promise and data management: export
/// the database, erase the selected year's data, or reset the entire app.
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

    var body: some View {
        @Bindable var backup = backup
        SettingsFocusScope(focus: focus) {
            Form {
                PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                    configuration: model.diagnosticReporting.effectiveConfiguration,
                ), disclosureInteraction: .linkToSettings)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                BackupSettingsSection(backup: backup, onExport: runExport)
                dataSection
                resetSection
            }
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
    }

    /// Build the archive before presenting it. The coordinator retains the
    /// file until the next export starts.
    private func runExport() {
        Task {
            if let url = await backup.exportBackup() {
                presentedShareItem = BackupShareSheet.Item(url: url)
            }
        }
    }

    private var eraseTitle: String {
        WhereFormat.settingsDataErase(year: report.selectedYear)
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(eraseTitle, systemSymbol: .trash)
            }
            .settingsRow(Item.eraseYear)
            .confirmationDialog(
                eraseTitle,
                isPresented: $showClearConfirmation,
                titleVisibility: .visible,
            ) {
                Button(eraseTitle, role: .destructive) {
                    Task { await report.clearSelectedYear() }
                }
                Button(String(localized: .settingsDataCancel), role: .cancel) {}
            } message: {
                Text(WhereFormat.settingsDataConfirmMessage(year: report.selectedYear))
            }
        } header: {
            Text(String(localized: .settingsDataHeader))
        } footer: {
            Text(WhereFormat.settingsDataFooter(year: report.selectedYear))
        }
    }

    /// Whole-app teardown: wipes every year's data and returns to first-run
    /// onboarding, run through the `LifecycleProxy` that `LifecycleContainer`
    /// publishes under `\.lifecycle`. The proxy asserts in debug / no-ops in
    /// release when no container is above (e.g. previews).
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(String(localized: .settingsResetErase), systemSymbol: .arrowCounterclockwise)
            }
            .settingsRow(Item.resetApp)
            .confirmationDialog(
                String(localized: .settingsResetErase),
                isPresented: $showResetConfirmation,
                titleVisibility: .visible,
            ) {
                Button(String(localized: .settingsResetConfirm), role: .destructive) {
                    requestReset()
                }
                Button(String(localized: .settingsDataCancel), role: .cancel) {}
            } message: {
                Text(String(localized: .settingsResetMessage))
            }
        } footer: {
            Text(String(localized: .settingsResetFooter))
        }
    }

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

#if DEBUG
    extension DataSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenRepresentative,
            ) {
                let world = SettingsPreviewWorld(theme: .standard, recordingWarning: .absent)
                NavigationStack {
                    DataSettingsView(
                        report: world.report,
                        backup: world.backup,
                    )
                }
                .whereEnvironment(world.environment(updates: nil, developer: nil))
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
            DataSettingsView(report: world.report, backup: world.backup)
        }
    }
#endif
