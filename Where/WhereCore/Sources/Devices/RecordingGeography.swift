import RegionKit

/// Effective geographic evidence before reporting groups non-primary regions as Other.
/// Explicit corrections can assert several named regions, unknown presence, or no presence.
public struct RecordingGeography: Hashable, Sendable {
    public enum ValidationError: Error { case reportingRegion }

    public let knownRegions: Set<Region>
    public let includesUnknownPresence: Bool

    public init(knownRegions: Set<Region>, includesUnknownPresence: Bool) throws {
        guard !knownRegions.contains(.other) else { throw ValidationError.reportingRegion }
        self.knownRegions = knownRegions
        self.includesUnknownPresence = includesUnknownPresence
    }

    public var presence: Set<Region> {
        includesUnknownPresence ? knownRegions.union([.other]) : knownRegions
    }

    /// Equal unknowns or exclusions do not prove that two devices were in the same region.
    public var establishesAgreement: Bool {
        !knownRegions.isEmpty && !includesUnknownPresence
    }

    public var singleRegion: Region? {
        establishesAgreement && knownRegions.count == 1 ? knownRegions.first : nil
    }
}
