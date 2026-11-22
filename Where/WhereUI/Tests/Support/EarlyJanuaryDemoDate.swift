import Foundation
import WhereCore

/// Demo lifecycle tests only need the first days of the year-to-date seed.
func earlyJanuaryDemoDate() -> Date {
    DayAggregator().calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
}
