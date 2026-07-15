import Foundation

public struct MissingDaysIssue: DataIssue, Hashable {
    public let range: MissingDayRange

    public init(range: MissingDayRange) {
        self.range = range
    }

    public var id: DataIssueID {
        .missingDays(start: range.start)
    }

    public var category: DataIssueCategory {
        .missingDays
    }

    public var sortKey: CalendarDay {
        range.start
    }

    public var isDismissible: Bool {
        false
    }

    public var resolution: IssueResolution {
        .backfill(range)
    }
}
