import Foundation
import RegionKit

/// User intent that the current stay in `region` continues through an inclusive
/// calendar day. The day is timezone-independent so travel cannot move the
/// asserted departure onto a neighboring date.
public struct PlannedStay: Hashable, Sendable, Codable {
    public let region: Region
    public let through: CalendarDay

    public init(region: Region, through: CalendarDay) {
        self.region = region
        self.through = through
    }
}
