import Foundation
import RegionKit

/// Independently editable travel intent. Both endpoint windows are inclusive,
/// and every permitted arrival precedes every permitted final day.
public struct PlannedStay: Hashable, Sendable, Codable, Identifiable {
    /// Stable identity across revisions, encoded as one UUID rather than a wrapper object.
    public struct ID: Hashable, Sendable, Codable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        /// A bare UUID is the persisted single-value identity shape.
        public init(from decoder: any Decoder) throws {
            rawValue = try UUID(from: decoder)
        }

        public func encode(to encoder: any Encoder) throws {
            try rawValue.encode(to: encoder)
        }
    }

    /// Earliest and latest choices for one timezone-independent endpoint.
    public struct DateWindow: Hashable, Sendable, Codable {
        public let earliest: CalendarDay
        public let latest: CalendarDay

        public var isExact: Bool {
            earliest == latest
        }

        public init(earliest: CalendarDay, latest: CalendarDay) throws {
            self.earliest = earliest
            self.latest = latest
            try validate()
        }

        public init(exact day: CalendarDay) {
            earliest = day
            latest = day
        }

        public func validate() throws {
            guard CalendarDay(iso: earliest.description) == earliest,
                  CalendarDay(iso: latest.description) == latest
            else { throw ValidationError.invalidDay }
            guard earliest <= latest else { throw ValidationError.reversedWindow }
        }
    }

    public enum ValidationError: Error, Equatable {
        case invalidDay
        case reversedWindow
        case arrivalAfterDeparture
        case unsupportedRegion
    }

    public let id: ID
    public let region: Region
    public let arrival: DateWindow
    public let departure: DateWindow

    public init(id: ID, region: Region, arrival: DateWindow, departure: DateWindow) throws {
        self.id = id
        self.region = region
        self.arrival = arrival
        self.departure = departure
        try validate()
    }

    /// Validate values at persistence boundaries after synthesized decoding.
    public func validate() throws {
        guard region != .other, Region(rawValue: region.rawValue) != nil else {
            throw ValidationError.unsupportedRegion
        }
        try arrival.validate()
        try departure.validate()
        guard arrival.latest <= departure.earliest else {
            throw ValidationError.arrivalAfterDeparture
        }
    }

    public var shortestRange: ClosedRange<CalendarDay> {
        arrival.latest ... departure.earliest
    }

    public var longestRange: ClosedRange<CalendarDay> {
        arrival.earliest ... departure.latest
    }

    public var dayCount: DayBounds {
        DayBounds(
            lower: arrival.latest.days(through: departure.earliest).count,
            upper: arrival.earliest.days(through: departure.latest).count,
        )
    }
}
