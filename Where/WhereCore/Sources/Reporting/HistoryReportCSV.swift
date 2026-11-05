import Foundation

/// A complete annual presence report encoded from one assessed history snapshot.
/// Each row represents one logical day in one region, without presentation grouping.
public struct HistoryReportCSV: Sendable, Equatable {
    public let year: Int
    public let data: Data

    init(report: YearReport) throws {
        try report.completeness.requireComplete()
        year = report.year
        var rows = ["calendar_day,region_id,region_name"]
        for day in report.days {
            for region in day.regions.sorted(by: { $0.rawValue < $1.rawValue }) {
                rows.append([
                    day.day.iso8601,
                    region.rawValue,
                    region.localizedName,
                ].map(Self.field).joined(separator: ","))
            }
        }
        data = Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// RFC-style CSV escaping. Catalog names can contain punctuation and non-ASCII text.
    static func field(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: {
            $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n"
        }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
