import RegionKit

/// The days, mapped points, and optional representative place behind one card.
public struct ElsewhereRegion: Hashable, Sendable, Identifiable {
    public let region: Region
    public let days: [DayPresence]
    public let locations: [RegionDayLocations]
    public let representativeCoordinate: Coordinate?

    public var id: Region {
        region
    }

    public init(
        region: Region,
        days: [DayPresence],
        locations: [RegionDayLocations],
        representativeCoordinate: Coordinate?,
    ) {
        self.region = region
        self.days = days
        self.locations = locations
        self.representativeCoordinate = representativeCoordinate
    }
}
