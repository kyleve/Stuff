import Foundation

extension Date {
    /// The start-of-day key for every calendar day in the inclusive range
    /// `self ... end`, evaluated in `calendar`. Both endpoints are normalized
    /// to start-of-day, so a same-day range yields a single element. Returns
    /// an empty array when `end` falls before `self`.
    ///
    /// Used to fan a date range out into per-day keys (e.g. backfilling a trip
    /// via `WhereController.addManualDays`).
    public func calendarDays(through end: Date, in calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: self)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }

        var days: [Date] = []
        var cursor = first
        while cursor <= last {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        return days
    }
}
