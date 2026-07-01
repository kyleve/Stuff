import SwiftUI
import WhereCore

/// Toolbar control for choosing which calendar year the reports cover. Reads
/// and drives the scene's `ReportModel`.
struct YearSelector: View {
    let report: ReportModel

    private var years: [Int] {
        let current = WhereModel.currentYear
        return Array((current - 5 ... current).reversed())
    }

    var body: some View {
        Menu {
            ForEach(years, id: \.self) { year in
                Button {
                    Task { await report.select(year: year) }
                } label: {
                    if year == report.selectedYear {
                        Label { Text(yearText(year)) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(yearText(year))
                    }
                }
            }
        } label: {
            Text(yearText(report.selectedYear))
        }
        .accessibilityIdentifier("where_year_selector")
    }

    /// Year without a grouping separator ("2026", not "2,026").
    private func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }
}

#if DEBUG
    #Preview {
        YearSelector(report: PreviewSupport.loadedReportModel())
    }
#endif
