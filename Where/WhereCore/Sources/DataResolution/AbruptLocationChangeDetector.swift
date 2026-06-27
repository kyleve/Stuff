import Foundation

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
