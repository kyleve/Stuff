import Foundation
import RegionKit

/// A single calendar day whose region set was inflated by cruise-speed GPS
/// fixes crossing untracked geography — i.e. a flight. `keepRegions` are the
/// real endpoints/dwell regions; `removedRegions` are the fly-over-only regions
/// the fix drops. `peakSpeedKMH` is the fastest leg, used for the detail view's
/// explanation copy.
public struct FlightDayIssue: DataIssue, Hashable {
    public let day: DayPresence
    public let keepRegions: Set<Region>
    public let removedRegions: Set<Region>
    public let peakSpeedKMH: Double

    public init(
        day: DayPresence,
        keepRegions: Set<Region>,
        removedRegions: Set<Region>,
        peakSpeedKMH: Double,
    ) {
        self.day = day
        self.keepRegions = keepRegions
        self.removedRegions = removedRegions
        self.peakSpeedKMH = peakSpeedKMH
    }

    public var id: DataIssueID {
        .flightDay(day: day.day)
    }

    public var category: DataIssueCategory {
        .flightDay
    }

    public var sortKey: CalendarDay {
        day.day
    }

    public var isDismissible: Bool {
        true
    }

    public var resolution: IssueResolution {
        .correctFlightDay(
            day: day,
            keepRegions: keepRegions,
            removedRegions: removedRegions,
            peakSpeedKMH: peakSpeedKMH,
        )
    }
}
