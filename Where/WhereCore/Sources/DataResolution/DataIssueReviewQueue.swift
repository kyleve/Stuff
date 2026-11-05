import Foundation

/// Retains ordinary issue work by category and logical dates, independently of derived IDs.
/// Recording-contract history supplies stable day semantics. This queue grants no write access.
public struct DataIssueReviewQueue: Sendable {
    public enum ValidationError: Error, Equatable {
        case emptyQueue
        case unknownIssue
        case invalidScope
        case unsupportedPolicy
        case differentServiceScope
        case dataGenerationChanged
        case incompatiblePolicy
        case incompleteAssessment
    }

    /// Durable original context. Decoded references require validation before restoration.
    public struct Reference: Hashable, Codable, Sendable {
        public let issueID: DataIssueID
        public let category: DataIssueCategory
        public let originalDays: Set<CalendarDay>
        public let context: RecordingReviewReference.Context

        fileprivate init(issue: any DataIssue, context: RecordingReviewReference.Context) throws {
            issueID = issue.id
            category = issue.category
            originalDays = try DataIssueReviewQueue.days(for: issue)
            self.context = context
            try validate()
        }

        public func validate() throws {
            guard !originalDays.isEmpty, (1 ... 9999).contains(context.historicalYear),
                  case let .days(queryDays) = context.query,
                  originalDays.allSatisfy(queryDays.contains)
            else { throw ValidationError.invalidScope }
            _ = try context.query.recordingPeriod()
            for day in originalDays {
                _ = try RecordingDayCoverage.searchPeriod(for: day)
            }
            switch issueID {
                case let .missingDays(start):
                    guard category == .missingDays, originalDays.min() == start,
                          MissingDays.ranges(Array(originalDays)).count == 1
                    else { throw ValidationError.invalidScope }
                case let .borderDrift(day):
                    guard category == .borderDrift, originalDays == [day]
                    else { throw ValidationError.invalidScope }
                case let .flightDay(day):
                    guard category == .flightDay, originalDays == [day]
                    else { throw ValidationError.invalidScope }
                case let .abruptChange(earlier, later):
                    guard category == .abruptChange, originalDays == [earlier, later]
                    else { throw ValidationError.invalidScope }
            }
        }
    }

    /// The current issue provides context; reviewDays bounds the dates offered for action.
    /// A merged missing-day range can contain gaps outside this set. Never replace it with
    /// the issue's full range or a minimum/maximum union.
    public struct Item: Sendable, Identifiable {
        public struct ID: Hashable, Sendable {
            public let issueID: DataIssueID
            public let reviewDays: Set<CalendarDay>
        }

        public let issue: any DataIssue
        public let reviewDays: Set<CalendarDay>
        public let references: Set<Reference>

        public var id: ID {
            ID(issueID: issue.id, reviewDays: reviewDays)
        }
    }

    public let references: Set<Reference>
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    private let scopeID: RecordingReviewSnapshot.ScopeID

    public init(issues: [any DataIssue], snapshot: HistoricalDataIssueScanResult) throws {
        guard !issues.isEmpty else { throw ValidationError.emptyQueue }
        guard snapshot.recording.policyVersion.major > 0 else {
            throw ValidationError.unsupportedPolicy
        }
        var references: Set<Reference> = []
        for issue in issues {
            let contexts = snapshot.years.filter { year in
                year.scan.issues.contains {
                    $0.id == issue.id && $0.category == issue.category && $0.resolution == issue
                        .resolution
                }
            }
            guard !contexts.isEmpty else { throw ValidationError.unknownIssue }
            for year in contexts {
                try references.insert(Reference(issue: issue, context: year.context))
            }
        }
        self.references = references
        generationID = snapshot.recording.generationID
        policyVersion = snapshot.recording.policyVersion
        scopeID = snapshot.recording.scopeID
    }

    /// A missing original year or a failed read cannot establish resolution. The caller must
    /// explicitly reassess original contexts even if ordinary history discovery drops a year.
    /// New categories are new work for the main list; splits and merges in the original
    /// category remain in this queue only on their original logical dates.
    public func remaining(in snapshot: HistoricalDataIssueScanResult) throws -> [Item] {
        guard snapshot.recording.scopeID == scopeID
        else { throw ValidationError.differentServiceScope }
        guard snapshot.recording.generationID == generationID else {
            throw ValidationError.dataGenerationChanged
        }
        guard snapshot.recording.policyVersion.major == policyVersion.major else {
            throw ValidationError.incompatiblePolicy
        }
        for reference in references {
            guard snapshot.years.contains(where: { $0.context == reference.context }) else {
                throw ValidationError.incompleteAssessment
            }
        }
        return try snapshot.issues.compactMap { issue in
            let days = try Self.days(for: issue)
            let relevant = references.filter {
                $0.category == issue.category && !$0.originalDays.isDisjoint(with: days)
            }
            let reviewDays = relevant.reduce(into: Set<CalendarDay>()) {
                $0.formUnion($1.originalDays.intersection(days))
            }
            guard !reviewDays.isEmpty else { return nil }
            return Item(issue: issue, reviewDays: reviewDays, references: relevant)
        }
    }

    private static func days(for issue: any DataIssue) throws -> Set<CalendarDay> {
        switch issue.resolution {
            case let .backfill(range):
                _ = try RecordingDayCoverage.searchPeriod(for: range.start)
                _ = try RecordingDayCoverage.searchPeriod(for: range.end)
                guard range.start <= range.end else { throw ValidationError.invalidScope }
                let days = Set(range.start.days(through: range.end))
                guard days.count == range.dayCount else { throw ValidationError.invalidScope }
                return days
            case let .correctSamples(proposal):
                _ = try RecordingDayCoverage.searchPeriod(for: proposal.day.day)
                return [proposal.day.day]
            case let .markTravelDay(earlier, later, _):
                _ = try RecordingDayCoverage.searchPeriod(for: earlier.day)
                _ = try RecordingDayCoverage.searchPeriod(for: later.day)
                return [earlier.day, later.day]
        }
    }
}
