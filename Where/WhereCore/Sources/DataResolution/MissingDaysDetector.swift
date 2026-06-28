import Foundation

public struct MissingDaysDetector: DataIssueDetector {
    public typealias Issue = MissingDaysIssue

    public init() {}

    public func detectIssues(in input: DataIssueInput) -> [MissingDaysIssue] {
        let currentYear = input.calendar.component(.year, from: input.now)
        // A future year hasn't begun, so nothing is "missing" yet. Guarding here
        // keeps the past-year branch (which runs through Dec 31) from flagging an
        // entire unstarted year as a gap.
        guard input.year <= currentYear else { return [] }

        let present = Set(input.report.days.map(\.date))
        let through: Date
        if input.year == currentYear {
            through = MissingDays.backlogCutoff(asOf: input.now, calendar: input.calendar)
        } else if
            let firstOfNextYear = input.calendar.date(
                from: DateComponents(year: input.year + 1, month: 1, day: 1),
            ),
            let lastOfYear = input.calendar.date(byAdding: .day, value: -1, to: firstOfNextYear)
        {
            through = lastOfYear
        } else {
            return []
        }

        return MissingDays.missingRanges(
            year: input.year,
            through: through,
            present: present,
            calendar: input.calendar,
        )
        .map { MissingDaysIssue(range: $0) }
    }
}
