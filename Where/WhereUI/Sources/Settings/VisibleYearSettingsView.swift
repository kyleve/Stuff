import SFSafeSymbols
import SwiftUI
import WhereCore

/// Settings drill-in for the report year. The year moved here off the
/// Primary/Elsewhere toolbars — it's set rarely, so it lives in Settings rather
/// than taking a permanent toolbar slot. Reuses `YearSelector`, which drives the
/// shared scene model, so changing it here updates every tab.
struct VisibleYearSettingsView: View {
    let report: YearReportModel
    var focus: SettingsFocus?

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                ReportYearSection(report: report)
            }
            .whereFormRoot()
        }
        .navigationTitle(String(localized: .settingsYearHeader))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension VisibleYearSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .year
    }

    enum Item: SettingsItem {
        case reportYear

        var title: String {
            switch self {
                case .reportYear: String(localized: .settingsYearHeader)
            }
        }

        var keywords: [String] {
            switch self {
                case .reportYear: splitKeywords(String(localized: .settingsKeywordsYear))
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            VisibleYearSettingsView(report: PreviewSupport.loadedYearReportModel())
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension VisibleYearSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            VisibleYearSettingsView.self,
            title: "Visible Year",
        ) { world in
            VisibleYearSettingsView(report: world.report)
        }
    }
#endif

private struct ReportYearSection: View {
    let report: YearReportModel

    var body: some View {
        Section {
            LabeledContent(String(localized: .settingsYearLabel)) {
                YearSelector(report: report)
            }
            .settingsRow(VisibleYearSettingsView.Item.reportYear)
        } header: {
            Text(String(localized: .settingsYearHeader))
        } footer: {
            Text(String(localized: .settingsYearFooter))
        }
    }
}

/// Toolbar control for choosing which calendar year the reports cover. Reads
/// and drives the scene's `YearReportModel`.
private struct YearSelector: View {
    let report: YearReportModel

    var body: some View {
        Menu {
            ForEach(report.selectableYears, id: \.self) { year in
                YearOptionButton(year: year, report: report)
            }
        } label: {
            Text(report.selectedYear.formatted(.number.grouping(.never)))
        }
        .accessibilityIdentifier("where_year_selector")
    }
}

private struct YearOptionButton: View {
    let year: Int
    let report: YearReportModel

    var body: some View {
        Button {
            Task { await report.select(year: year) }
        } label: {
            if year == report.selectedYear {
                Label { Text(year.formatted(.number.grouping(.never))) } icon: {
                    Image(systemSymbol: .checkmark)
                }
            } else {
                Text(year.formatted(.number.grouping(.never)))
            }
        }
    }
}

#if DEBUG
    #Preview {
        YearSelector(report: PreviewSupport.loadedYearReportModel())
    }
#endif
