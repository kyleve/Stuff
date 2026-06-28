import Foundation

/// One recorded point inside a region: its coordinate plus the originating
/// fix's horizontal accuracy in meters, so the UI can draw a GPS uncertainty
/// radius around it. A named struct (rather than a bare `Coordinate` or a
/// `(Coordinate, Double)` tuple) so the accuracy travels with the point through
/// the value-type boundary.
public struct RegionDayPoint: Hashable, Sendable {
    public let coordinate: Coordinate
    /// The fix's horizontal accuracy in meters (the radius of the 68%
    /// confidence circle, per `CLLocation`). Larger means a coarser fix.
    public let horizontalAccuracy: Double

    public init(coordinate: Coordinate, horizontalAccuracy: Double) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
    }
}

/// The raw points recorded inside one region on one calendar day.
///
/// Where `DayPresence` collapses a day to the *set of regions* it touched,
/// this keeps the underlying points so the UI can answer "where, exactly?" —
/// dropping pins on a map (with their GPS uncertainty radius) and
/// reverse-geocoding a representative point into a place name. Produced by
/// `DayAggregator.locations(in:samples:attributor:)`.
public struct RegionDayLocations: Hashable, Sendable, Identifiable {
    /// Start-of-day for the points, in the producing aggregator's calendar.
    public let date: Date
    /// Every sample that fell inside the region on this day, in the order the
    /// samples were supplied (typically chronological).
    public let points: [RegionDayPoint]

    public var id: Date {
        date
    }

    public init(date: Date, points: [RegionDayPoint]) {
        self.date = date
        self.points = points
    }
}
