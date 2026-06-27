import SwiftUI
import WhereCore

/// Toolbar control for choosing which calendar year the reports cover. Reads
/// and drives the shared `WhereSession`.
struct YearSelector: View {
    @Environment(WhereSession.self) private var session

    private var years: [Int] {
        let current = WhereModel.currentYear
        return Array((current - 5 ... current).reversed())
    }

    var body: some View {
        Menu {
            ForEach(years, id: \.self) { year in
                Button {
                    Task { await session.select(year: year) }
                } label: {
                    if year == session.selectedYear {
                        Label { Text(yearText(year)) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(yearText(year))
                    }
                }
            }
        } label: {
            Text(yearText(session.selectedYear))
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
        YearSelector()
            .environment(PreviewSupport.loadedSession())
    }
#endif
