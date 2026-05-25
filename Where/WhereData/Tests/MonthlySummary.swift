import Foundation
import WhereCore

/// Compact, human-readable rollup of a `YearReport` for snapshot diffing.
/// Stable string output (sorted regions, fixed format) so changes are easy
/// to spot in PR review.
struct MonthlySummary: Hashable {
    let year: Int
    let months: [Month]

    struct Month: Hashable {
        let number: Int
        let daysWithData: Int
        let dualRegionDays: Int
        let totals: [Bucket]
    }

    struct Bucket: Hashable {
        let region: Region
        let count: Int
    }

    static func from(report: YearReport, calendar: Calendar) -> MonthlySummary {
        var monthly: [Int: (days: Set<Date>, dualDays: Int, totals: [Region: Int])] = [:]
        for day in report.days {
            let m = calendar.component(.month, from: day.date)
            var entry = monthly[m] ?? (days: [], dualDays: 0, totals: [:])
            entry.days.insert(day.date)
            if day.regions.count > 1 {
                entry.dualDays += 1
            }
            for region in day.regions {
                entry.totals[region, default: 0] += 1
            }
            monthly[m] = entry
        }
        let sorted = monthly.keys.sorted().map { m -> Month in
            let entry = monthly[m] ?? (days: [], dualDays: 0, totals: [:])
            let buckets = entry.totals
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { Bucket(region: $0.key, count: $0.value) }
            return Month(
                number: m,
                daysWithData: entry.days.count,
                dualRegionDays: entry.dualDays,
                totals: buckets,
            )
        }
        return MonthlySummary(year: report.year, months: sorted)
    }

    var text: String {
        var lines = ["Year \(year):"]
        for month in months {
            let regions = month.totals
                .map { "\($0.region.rawValue)=\($0.count)" }
                .joined(separator: " ")
            lines.append(
                "  Month \(String(format: "%02d", month.number)) "
                    + "(\(month.daysWithData) days, "
                    + "\(month.dualRegionDays) dual-region): "
                    + regions,
            )
        }
        return lines.joined(separator: "\n")
    }
}
