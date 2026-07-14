import Foundation

/// Detects calendar days with no recorded presence and reports them as
/// `MissingDaysIssue` backfill ranges.
///
/// Scans from Jan 1 of `input.year` to a cutoff and groups the absent days into
/// contiguous ranges: the current year stops at `MissingDays.backlogCutoff` (a
/// grace window so the most recent day or two aren't nagged about immediately),
/// a past year runs through Dec 31, and a future year (which hasn't begun)
/// yields nothing.
public struct MissingDaysDetector: DataIssueDetector {
    public typealias Issue = MissingDaysIssue

    public init() {}

    public func detectIssues(in input: DataIssueInput) -> [MissingDaysIssue] {
        let currentYear = input.calendar.component(.year, from: input.now)
        // A future year hasn't begun, so nothing is "missing" yet. Guarding here
        // keeps the past-year branch (which runs through Dec 31) from flagging an
        // entire unstarted year as a gap.
        guard input.year <= currentYear else { return [] }

        let present = Set(input.report.days.map(\.day))
        let through: CalendarDay = if input.year == currentYear {
            MissingDays.backlogCutoff(asOf: input.now, calendar: input.calendar)
        } else {
            // A past year runs through its final day.
            CalendarDay(year: input.year, month: 12, day: 31)
        }

        return MissingDays.missingRanges(
            year: input.year,
            through: through,
            present: present,
        )
        .map { MissingDaysIssue(range: $0) }
    }
}
