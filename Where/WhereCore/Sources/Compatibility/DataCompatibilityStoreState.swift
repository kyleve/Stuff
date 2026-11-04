/// Shared monotonic requirements and the major headers present in immutable history envelopes.
public struct DataCompatibilityStoreState: Hashable, Sendable {
    public let persistedRequiredMajor: UInt?
    public let recordMajors: Set<UInt>
    public let hasLegacyHistory: Bool

    public var requiredMajor: UInt {
        max(persistedRequiredMajor ?? 0, recordMajors.max() ?? 0)
    }

    public init(persistedRequiredMajor: UInt?, recordMajors: Set<UInt>, hasLegacyHistory: Bool) {
        self.persistedRequiredMajor = persistedRequiredMajor
        self.recordMajors = recordMajors
        self.hasLegacyHistory = hasLegacyHistory
    }

    public func validate(policy: DataCompatibilityPolicy) throws {
        // Unversioned tables are shared by current contracts. Their presence establishes
        // legacy initialization only before a dataset has a verified requirement.
        if persistedRequiredMajor != nil || !recordMajors.isEmpty {
            try policy.validate(requiredMajor: requiredMajor)
        }
        for major in recordMajors.sorted() {
            try policy.validate(requiredMajor: major)
        }
    }
}
