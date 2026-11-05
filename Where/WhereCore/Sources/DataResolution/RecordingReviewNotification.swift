import Foundation

/// Durable original work for a recording notification. This is local routing context, never
/// a history write grant. Rebind only after admission and a fresh assessment of every period.
public struct RecordingReviewNotification: Hashable, Codable, Sendable, Identifiable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    /// Separate accounts can share the initial generation. Container, store, and account
    /// identity must all match; a local dataset never matches a shared dataset.
    public enum Binding: Hashable, Codable, Sendable {
        case local(storeID: DataCompatibilityDataset.StoreID)
        case cloudKit(
            storeID: DataCompatibilityDataset.StoreID,
            containerIdentifier: String,
            accountID: DataCompatibilityAccountID,
        )

        func validate() throws {
            switch self {
                case let .local(storeID):
                    guard !storeID.rawValue.isEmpty else { throw ValidationError.invalidBinding }
                case let .cloudKit(storeID, containerIdentifier, accountID):
                    guard !storeID.rawValue.isEmpty, !containerIdentifier.isEmpty,
                          !accountID.rawValue.isEmpty
                    else { throw ValidationError.invalidBinding }
            }
        }
    }

    public struct Reference: Hashable, Codable, Sendable {
        public let issueID: RecordingIssue.ID
        public let originalPeriods: [RecordingPeriod]
        public let context: RecordingReviewReference.Context

        fileprivate init(_ reference: RecordingReviewReference) {
            issueID = reference.issueID
            originalPeriods = reference.originalPeriods
            context = reference.context
        }

        func validate() throws {
            try issueID.period.validate()
            guard !originalPeriods.isEmpty else {
                throw RecordingReviewReference.ValidationError.emptyScope
            }
            let queryPeriod = try context.query.recordingPeriod()
            for period in originalPeriods {
                try period.validate()
                guard issueID.period.start <= period.start, period.end <= issueID.period.end else {
                    throw RecordingReviewReference.ValidationError.scopeOutsideIssue
                }
                guard queryPeriod.start <= period.start, period.end <= queryPeriod.end else {
                    throw RecordingReviewReference.ValidationError.scopeOutsideQuery
                }
            }
            guard (1 ... 9999).contains(context.historicalYear) else {
                throw ValidationError.invalidHistoricalYear
            }
        }
    }

    public enum ValidationError: Error, Equatable {
        case unsupportedFormat
        case invalidBinding
        case differentDataset
        case invalidHistoricalYear
    }

    public let id: ID
    public let binding: Binding
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    public let references: Set<Reference>
    private let formatVersion: UInt

    public var originalPeriods: [RecordingPeriod] {
        RecordingPeriod.union(references.flatMap(\.originalPeriods))
    }

    public init(references: [RecordingReviewReference], binding: Binding) throws {
        // Also rejects mixed live scopes, generations, or incompatible policy versions.
        _ = try RecordingReviewQueue(references: references)
        guard let first = references.first
        else { throw RecordingReviewQueue.ValidationError.emptyQueue }
        id = ID(rawValue: UUID())
        self.binding = binding
        generationID = first.generationID
        policyVersion = first.policyVersion
        self.references = Set(references.map(Reference.init))
        formatVersion = 1
        try validate()
    }

    /// Call before persistence and after synthesized decoding, which bypasses the initializer.
    public func validate() throws {
        guard formatVersion == 1 else { throw ValidationError.unsupportedFormat }
        try binding.validate()
        guard !references.isEmpty else { throw RecordingReviewQueue.ValidationError.emptyQueue }
        for reference in references {
            try reference.validate()
        }
    }

    /// An admitted caller supplies its current binding and fully assessed original periods.
    /// Successful empty reassessment means resolved; missing coverage or another dataset throws.
    /// Preserve the old issue IDs and query contexts even when the new issues have moved.
    public func restore(
        binding currentBinding: Binding,
        snapshot: RecordingReviewSnapshot,
    ) throws -> RecordingReviewQueue {
        try validate()
        try currentBinding.validate()
        guard binding == currentBinding else { throw ValidationError.differentDataset }
        guard generationID == snapshot.generationID else {
            throw RecordingReviewQueue.ValidationError.dataGenerationChanged
        }
        guard policyVersion.major == snapshot.policyVersion.major else {
            throw RecordingReviewQueue.ValidationError.incompatiblePolicy
        }
        guard snapshot.covers(originalPeriods) else {
            throw RecordingReviewQueue.ValidationError.incompleteAssessment
        }
        return try RecordingReviewQueue(references: references.map {
            RecordingReviewReference(
                saved: $0,
                scopeID: snapshot.scopeID,
                generationID: generationID,
                policyVersion: policyVersion,
            )
        })
    }
}
