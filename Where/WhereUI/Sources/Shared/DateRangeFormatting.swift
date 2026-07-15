import Foundation
import WhereCore

enum DateRangeFormatting {
    /// Abbreviated month/day span, e.g. "Jan 3" or "Jan 3 – Jan 7".
    static func abbreviated(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(format)
        }
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    /// Abbreviated month/day span for a `CalendarDay` range, resolved in
    /// `calendar` for display.
    static func abbreviated(
        start: CalendarDay,
        end: CalendarDay,
        calendar: Calendar = .current,
    ) -> String {
        abbreviated(
            start: start.startOfDay(in: calendar),
            end: end.startOfDay(in: calendar),
            calendar: calendar,
        )
    }
}

extension CalendarDay {
    /// A `Date` for display formatting, resolved in the current calendar.
    /// Presentation only — identity and logic use `CalendarDay` directly.
    var displayDate: Date {
        startOfDay(in: .current)
    }
}

extension DayPresence {
    /// The presence's day as a `Date` for display formatting (see
    /// `CalendarDay.displayDate`).
    var displayDate: Date {
        day.displayDate
    }
}
