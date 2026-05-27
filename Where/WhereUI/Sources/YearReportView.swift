import SwiftUI
import WhereCore

/// Renders a single `YearReport`: per-region day totals followed by the
/// list of recorded days and the regions each day counted for.
struct YearReportView: View {
    let report: YearReport

    var body: some View {
        if report.days.isEmpty {
            ContentUnavailableView(
                "No location data",
                systemImage: "mappin.slash",
                description: Text("No days have been recorded for \(verbatimYear)."),
            )
        } else {
            List {
                Section("Days counted") {
                    ForEach(rankedTotals) { total in
                        HStack {
                            RegionLabel(region: total.region)
                            Spacer()
                            Text("^[\(total.count) day](inflect: true)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Days") {
                    ForEach(report.days, id: \.date) { day in
                        DayRow(day: day)
                    }
                }
            }
        }
    }

    private var verbatimYear: String { String(report.year) }

    /// Regions with at least one day this year, ranked by day count
    /// (descending) and then localized name for a stable tie-break.
    private var rankedTotals: [RegionTotal] {
        Region.allCases
            .compactMap { region in
                let count = report.totals[region] ?? 0
                guard count > 0 else { return nil }
                return RegionTotal(region: region, count: count)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.region.localizedName < rhs.region.localizedName
            }
    }
}

/// A region paired with the number of days it counted for. A named
/// struct rather than a tuple because it is a `ForEach` element type
/// (see the repo's "small named structs over tuples" convention).
private struct RegionTotal: Identifiable {
    let region: Region
    let count: Int

    var id: Region { region }
}

private struct DayRow: View {
    let day: DayPresence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date, format: .dateTime.weekday().month().day())
                .font(.headline)
            Text(regionNames)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var regionNames: String {
        day.regions
            .map(\.localizedName)
            .sorted()
            .joined(separator: " · ")
    }
}
