import LifecycleKit
import SwiftUI
import WhereCore

/// Settings drill-in for the destructive actions: erase the selected year's data,
/// or erase everything and return to first-run setup.
struct DataSettingsView: View {
    let report: YearReportModel
    var focus: SettingsFocus?

    @Environment(WhereModel.self) private var model
    @Environment(\.lifecycleRunner) private var runner

    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                dataSection
                resetSection
            }
        }
        .navigationTitle(String(localized: .settingsDataHeader))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var eraseTitle: String {
        WhereFormat.settingsDataErase(year: report.selectedYear)
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(eraseTitle, systemImage: "trash")
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
    /// onboarding, run through the `LifecycleRunner` published into the
    /// environment by `LifecycleContainer`. The runner proxy asserts in debug /
    /// no-ops in release when no container is above (e.g. previews).
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(String(localized: .settingsResetErase), systemImage: "arrow.counterclockwise")
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
        Task { await runner.teardown(WhereLaunch.resetSequence(for: model)) }
    }
}

extension DataSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .data
    }

    enum Item: SettingsItem {
        case eraseYear
        case resetApp

        var title: String {
            switch self {
                case .eraseYear: String(localized: .settingsEraseYearTitle)
                case .resetApp: String(localized: .settingsResetErase)
            }
        }

        var keywords: [String] {
            switch self {
                case .eraseYear: splitKeywords(String(localized: .settingsKeywordsEraseYear))
                case .resetApp: splitKeywords(String(localized: .settingsKeywordsReset))
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            DataSettingsView(report: PreviewSupport.loadedYearReportModel())
                .environment(PreviewSupport.loadedModel())
        }
        .whereBroadwayRoot()
    }
#endif
