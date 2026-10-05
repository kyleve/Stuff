import Foundation
import RegionKit

/// One immutable revision of a GPS sample's attribution. Nil restores automatic
/// attribution, an empty set excludes the sample from presence, and a nonempty set
/// replaces its attributed regions. Reset tombstones outlive delayed older revisions.
public struct SampleAttributionRevision: Identifiable, Hashable, Codable, Sendable {
    /// One millisecond makes a local write newer than observed history when
    /// its clock has not advanced. UUID ordering remains the concurrent tie-breaker.
    private static let minimumTimestampAdvance: TimeInterval = 0.001

    /// Stable identity for one immutable attribution revision. The single-value
    /// Codable conformance preserves the bare UUID used in backup archives.
    public struct ID: RawRepresentable, Codable, Sendable, Hashable, Comparable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public static func < (lhs: ID, rhs: ID) -> Bool {
            lhs.rawValue.uuidString < rhs.rawValue.uuidString
        }
    }

    public let id: ID
    public let sampleID: UUID
    public let updatedAt: Date
    public let replacementRegions: Set<Region>?

    public init(
        id: ID,
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
        return lhs.id > rhs.id
    }

    /// Advance the observed register before applying either a correction or reset.
    static func nextUpdatedAt(now: Date, after revision: SampleAttributionRevision?) -> Date {
        guard let revision else { return now }
        return max(now, revision.updatedAt.addingTimeInterval(minimumTimestampAdvance))
    }
}
