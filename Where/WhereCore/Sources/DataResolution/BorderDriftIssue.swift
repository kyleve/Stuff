import Foundation
import RegionKit

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
        .borderDrift(day: day.day)
    }

    public var category: DataIssueCategory {
        .borderDrift
    }

    public var sortKey: CalendarDay {
        day.day
    }

    public var isDismissible: Bool {
        true
    }

    public var resolution: IssueResolution {
        // Drop the spurious `.other` while keeping whatever real regions the
        // day already counts for. A pure-`.other` day has nothing left, so it
        // falls back to the nearest primary region as the suggested label.
        let realRegions = day.regions.subtracting([.other])
        return .relabelDay(
            day: day,
            suggestedRegions: realRegions.isEmpty ? [nearestRegion] : realRegions,
            approximateMeters: distanceMeters,
        )
    }
}
