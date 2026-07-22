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
        .navigationTitle(Strings.settingsDataHeader)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var eraseTitle: String {
        Strings.settingsDataErase(year: report.selectedYear)
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
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsDataConfirmMessage(year: report.selectedYear))
            }
        } header: {
            Text(Strings.settingsDataHeader)
        } footer: {
            Text(Strings.settingsDataFooter(year: report.selectedYear))
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
                Label(Strings.settingsResetErase, systemImage: "arrow.counterclockwise")
            }
            .settingsRow(Item.resetApp)
            .confirmationDialog(
                Strings.settingsResetErase,
                isPresented: $showResetConfirmation,
                titleVisibility: .visible,
            ) {
                Button(Strings.settingsResetConfirm, role: .destructive) {
                    requestReset()
                }
                Button(Strings.settingsDataCancel, role: .cancel) {}
            } message: {
                Text(Strings.settingsResetMessage)
            }
        } footer: {
            Text(Strings.settingsResetFooter)
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
                case .eraseYear: Strings.settingsEraseYearTitle
                case .resetApp: Strings.settingsResetErase
            }
        }

        var keywords: [String] {
            switch self {
                case .eraseYear: splitKeywords(Strings.settingsKeywordsEraseYear)
                case .resetApp: splitKeywords(Strings.settingsKeywordsReset)
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
