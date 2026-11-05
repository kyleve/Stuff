import Foundation
import RegionKit

/// A raw observation joined to its effective region attribution. An empty
/// set excludes presence without removing the original trajectory evidence.
public struct AttributedLocationSample: Hashable, Sendable {
    public enum Day: Hashable, Sendable {
        /// Foundation history and non-GPS assertions retain the existing viewing-calendar rule.
        case viewingCalendar
        /// The selected effective day can come from raw context or a reviewed calendar decision.
        case recording(CalendarDay)
    }

    public let sample: LocationSample
    public let regions: Set<Region>
    public let day: Day

    public init(sample: LocationSample, regions: Set<Region>) {
        self.init(sample: sample, regions: regions, day: .viewingCalendar)
    }

    public init(sample: LocationSample, regions: Set<Region>, day: Day) {
        self.sample = sample
        self.regions = regions
        self.day = day
    }

    public func calendarDay(in calendar: Calendar) -> CalendarDay {
        switch day {
            case .viewingCalendar: CalendarDay(from: sample.timestamp, in: calendar)
            case let .recording(day): day
        }
    }

    public func replacingRegions(_ regions: Set<Region>) -> Self {
        Self(sample: sample, regions: regions, day: day)
    }

    static func raw(_ samples: [LocationSample], attributor: any RegionAttributing) -> [Self] {
        samples.map { Self(sample: $0, regions: [attributor.region(at: $0.coordinate)]) }
    }
}
