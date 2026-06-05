import Foundation

/// The set of regions the user was in on a particular calendar day.
///
/// `regions` is a `Set` because we want union semantics (a day in CA + NY
/// counts for both).
public struct DayPresence: Hashable, Sendable, Codable {
    /// Start-of-day in whichever calendar/timezone produced this value.
    public let date: Date
    public let regions: Set<Region>

    public init(date: Date, regions: Set<Region>) {
        self.date = date
        self.regions = regions
    }
}
