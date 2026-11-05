import Foundation
import WhereCore

enum DateRangeFormatting {
    /// Abbreviated month/day span, e.g. "Jan 3" or "Jan 3 – Jan 7".
    static func abbreviated(start: Date, end: Date, calendar: Calendar = .current) -> String {
        var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(format)
        }
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    /// The logical date label is independent of the viewer's zone and preferred calendar.
    static func abbreviated(
        start: CalendarDay,
        end: CalendarDay,
    ) -> String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let first = WhereFormat.calendarDay(start, format: format)
        guard start != end else { return first }
        return "\(first) – \(WhereFormat.calendarDay(end, format: format))"
    }
}
