import Foundation

/// Detects calendar-adjacent days whose regions are completely disjoint — e.g.
/// California one day and New York the next with no overlap — and reports an
/// `AbruptChangeIssue` suggesting the boundary was actually a travel day.
///
/// Walks the day-sorted report comparing each day to the following one, flagging
/// a pair only when both have regions, the two sets share nothing, and the days
/// are exactly one calendar day apart (a gap in the calendar is left alone).
public struct AbruptLocationChangeDetector: DataIssueDetector {
    public typealias Issue = AbruptChangeIssue

    public init() {}

    public func detectIssues(in input: DataIssueInput) -> [AbruptChangeIssue] {
        let sortedDays = input.report.days.sorted { $0.date < $1.date }
        guard sortedDays.count >= 2 else { return [] }

        var issues: [AbruptChangeIssue] = []
        for index in sortedDays.indices.dropLast() {
            let earlier = sortedDays[index]
            let later = sortedDays[index + 1]
            guard
                !earlier.regions.isEmpty,
                !later.regions.isEmpty,
                earlier.regions.isDisjoint(with: later.regions),
                isCalendarAdjacent(earlier.date, later.date, calendar: input.calendar)
            else { continue }

            issues.append(AbruptChangeIssue(earlierDay: earlier, laterDay: later))
        }
        return issues
    }

    private func isCalendarAdjacent(_ earlier: Date, _ later: Date, calendar: Calendar) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: earlier) else { return false }
        return calendar.isDate(next, inSameDayAs: later)
    }
}
