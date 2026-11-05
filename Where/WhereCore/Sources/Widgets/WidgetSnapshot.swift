import Foundation
import RegionKit

/// One logical day's widget publication. Unresolved scopes cannot carry authoritative counts.
/// The enum case names form the local wire format; a future shape change replaces this cache.
public struct WidgetSnapshot: Hashable, Sendable, Codable {
    public enum Value<Content: Hashable & Sendable & Codable>: Hashable, Sendable, Codable {
        case complete(Content)
        case needsReview
    }

    public struct Assessment: Hashable, Sendable, Codable {
        public let version: DataSemanticsVersion
        public let dayRegions: Value<Set<Region>>
        public let totals: Value<[Region: Int]>
        public let appearances: [Region: RegionAppearance]
    }

    public enum History: Hashable, Sendable, Codable {
        case unavailable
        case assessed(Assessment)
    }

    public let day: CalendarDay
    public let history: History

    public var year: Int {
        day.year
    }

    public var assessment: Assessment? {
        switch history {
            case .unavailable: nil
            case let .assessed(assessment): assessment
        }
    }

    public var appearances: [Region: RegionAppearance] {
        assessment?.appearances ?? [:]
    }

    public init(day: CalendarDay, history: History) {
        self.day = day
        self.history = history
    }

    public init(
        day: CalendarDay,
        version: DataSemanticsVersion,
        dayRegions: Value<Set<Region>>,
        totals: Value<[Region: Int]>,
        appearances: [Region: RegionAppearance] = [:],
    ) {
        self.init(day: day, history: .assessed(Assessment(
            version: version,
            dayRegions: dayRegions,
            totals: totals,
            appearances: appearances,
        )))
    }
}
