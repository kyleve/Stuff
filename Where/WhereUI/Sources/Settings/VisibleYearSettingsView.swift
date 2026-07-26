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
                Section {
                    LabeledContent(String(localized: .settingsYearLabel)) {
                        YearSelector(report: report)
                    }
                    .settingsRow(Item.reportYear)
                } header: {
                    Text(String(localized: .settingsYearHeader))
                } footer: {
                    Text(String(localized: .settingsYearFooter))
                }
            }
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
