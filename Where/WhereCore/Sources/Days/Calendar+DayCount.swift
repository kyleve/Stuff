import Foundation

extension Calendar {
    /// The number of days in `year` (365, or 366 in a leap year), evaluated in
    /// this calendar. Derived from the calendar's own day-of-year range rather
    /// than assuming a fixed length, so leap years come out right.
    ///
    /// The `366`/`365` split falls out of `range(of:.day, in:.year, for:)`; the
    /// literal fallback is an unreachable release safety net for a calendar that
    /// can't even resolve a mid-year date (an impossible state we assert on in
    /// debug rather than paper over).
    public func dayCount(ofYear year: Int) -> Int {
        guard
            let midYear = date(from: DateComponents(year: year, month: 6, day: 15)),
            let range = range(of: .day, in: .year, for: midYear)
        else {
            assertionFailure("Calendar could not resolve the day range for year \(year)")
            return 365
        }
        return range.count
    }
}
