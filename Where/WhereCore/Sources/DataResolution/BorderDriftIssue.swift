import Foundation

public struct BorderDriftIssue: DataIssue, Hashable {
    public let day: DayPresence
    public let nearestRegion: Region
    public let distanceMeters: Double

    public init(day: DayPresence, nearestRegion: Region, distanceMeters: Double) {
        self.day = day
        self.nearestRegion = nearestRegion
        self.distanceMeters = distanceMeters
    }

    public var id: DataIssueID {
        .borderDrift(date: day.date)
    }

    public var category: DataIssueCategory {
        .borderDrift
    }

    public var sortKey: Date {
        day.date
    }

    public var isDismissible: Bool {
        true
    }

    public var resolution: IssueResolution {
        .relabelDay(
            day: day,
            suggestedRegions: [nearestRegion],
            approximateMeters: distanceMeters,
        )
    }
}
