import Foundation

enum DateRangeFormatting {
    /// Abbreviated month/day span, e.g. "Jan 3" or "Jan 3 – Jan 7".
    static func abbreviated(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(format)
        }
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }
}
