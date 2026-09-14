import Foundation
import RegionKit

/// One immutable revision of a GPS sample's attribution. Nil restores automatic
/// attribution, an empty set excludes the sample from presence, and a nonempty set
/// replaces its attributed regions. Reset tombstones outlive delayed older revisions.
public struct SampleAttributionRevision: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let sampleID: UUID
    public let updatedAt: Date
    public let replacementRegions: Set<Region>?

    public init(
        id: UUID,
        sampleID: UUID,
        updatedAt: Date,
        replacementRegions: Set<Region>?,
    ) {
        self.id = id
        self.sampleID = sampleID
        self.updatedAt = updatedAt
        self.replacementRegions = replacementRegions
    }

    /// Deterministic last-writer ordering for concurrent CloudKit revisions.
    public static func newer(
        _ lhs: SampleAttributionRevision,
        than rhs: SampleAttributionRevision,
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
