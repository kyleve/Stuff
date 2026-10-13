import Foundation
import RegionKit

/// A revision of the forecast home choice. Nil selects historical estimates and
/// remains persisted so delayed sync cannot restore a superseded home region.
public struct HomeRegionRecord: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let region: Region?
    public let updatedAt: Date

    public init(id: UUID, region: Region?, updatedAt: Date) throws {
        self.id = id
        self.region = region
        self.updatedAt = updatedAt
        try validate()
    }

    public func validate() throws {
        if let region {
            guard region != .other, Region(rawValue: region.rawValue) != nil else {
                throw PlannedStay.ValidationError.unsupportedRegion
            }
        }
    }

    public static func newer(_ lhs: HomeRegionRecord, than rhs: HomeRegionRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
