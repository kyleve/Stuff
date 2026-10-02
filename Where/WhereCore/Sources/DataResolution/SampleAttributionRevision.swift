import Foundation
import IdentityKit
import RegionKit

/// One immutable revision of a GPS sample's attribution. Nil restores automatic
/// attribution, an empty set excludes the sample from presence, and a nonempty set
/// replaces its attributed regions. Reset tombstones outlive delayed older revisions.
public struct SampleAttributionRevision: Identifiable, Hashable, Codable, Sendable {
    /// One millisecond makes a local write newer than observed history when
    /// its clock has not advanced. UUID ordering remains the concurrent tie-breaker.
    private static let minimumTimestampAdvance: TimeInterval = 0.001

    /// Stable identity for one immutable correction, distinct from its target sample.
    public typealias ID = TypedID<SampleAttributionRevision>

    public let id: ID
    public let sampleID: LocationSample.ID
    public let updatedAt: Date
    public let replacementRegions: Set<Region>?

    public init(
        id: ID,
        sampleID: LocationSample.ID,
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
        return lhs.id > rhs.id
    }

    /// Advance the observed register before applying either a correction or reset.
    static func nextUpdatedAt(now: Date, after revision: SampleAttributionRevision?) -> Date {
        guard let revision else { return now }
        return max(now, revision.updatedAt.addingTimeInterval(minimumTimestampAdvance))
    }
}
