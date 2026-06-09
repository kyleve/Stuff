import Foundation

/// The raw coordinates recorded inside one region on one calendar day.
///
/// Where `DayPresence` collapses a day to the *set of regions* it touched,
/// this keeps the underlying points so the UI can answer "where, exactly?" —
/// dropping pins on a map and reverse-geocoding a representative point into a
/// place name. Produced by `DayAggregator.locations(in:samples:attributor:)`.
public struct RegionDayLocations: Hashable, Sendable, Identifiable {
    /// Start-of-day for the points, in the producing aggregator's calendar.
    public let date: Date
    /// Every sample coordinate that fell inside the region on this day, in
    /// the order the samples were supplied (typically chronological).
    public let coordinates: [Coordinate]

    public var id: Date {
        date
    }

    public init(date: Date, coordinates: [Coordinate]) {
        self.date = date
        self.coordinates = coordinates
    }
}
