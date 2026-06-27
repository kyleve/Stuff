import Foundation

public struct AbruptChangeIssue: DataIssue, Hashable {
    public let earlierDay: DayPresence
    public let laterDay: DayPresence

    public init(earlierDay: DayPresence, laterDay: DayPresence) {
        self.earlierDay = earlierDay
        self.laterDay = laterDay
    }

    public var id: DataIssueID {
        .abruptChange(earlier: earlierDay.date, later: laterDay.date)
    }

    public var category: DataIssueCategory {
        .abruptChange
    }

    public var sortKey: Date {
        laterDay.date
    }

    public var isDismissible: Bool {
        true
    }

    public var resolution: IssueResolution {
        .markTravelDay(
            earlier: earlierDay,
            later: laterDay,
            suggestedRegions: earlierDay.regions.union(laterDay.regions),
        )
    }
}
