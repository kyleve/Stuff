import SwiftUI
import WhereCore

/// Toolbar control for choosing which calendar year the reports cover. Reads
/// and drives the shared `WhereModel`.
struct YearSelector: View {
    @Environment(WhereModel.self) private var model

    private var years: [Int] {
        let current = WhereModel.currentYear
        return Array((current - 5 ... current).reversed())
    }

    var body: some View {
        Menu {
            ForEach(years, id: \.self) { year in
                Button {
                    Task { await model.select(year: year) }
                } label: {
                    if year == model.selectedYear {
                        Label { Text(yearText(year)) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(yearText(year))
                    }
                }
            }
        } label: {
            Label { Text(yearText(model.selectedYear)) } icon: { Image(systemName: "calendar")
            }
        }
        .accessibilityIdentifier("where_year_selector")
    }

    /// Year without a grouping separator ("2026", not "2,026").
    private func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }
}
