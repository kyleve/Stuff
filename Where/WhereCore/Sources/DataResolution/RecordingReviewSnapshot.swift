import Foundation

/// A successful assessment of explicit absolute periods. Empty issues establish resolution
/// only inside these periods and this admitted service lifetime, generation, and policy.
public struct RecordingReviewSnapshot: Hashable, Sendable {
    /// Created once by the read owner. Separate accounts can share an initial generation ID.
    public struct ScopeID: Hashable, Sendable {
        let rawValue: UUID
    }

    public enum ValidationError: Error, Equatable {
        case emptyAssessment
        case issueOutsideAssessment
    }

    public let scopeID: ScopeID
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    public let assessedPeriods: [RecordingPeriod]
    public let issues: [RecordingIssue]

    init(
        scopeID: ScopeID,
        generationID: WhereDataGenerationID,
        policyVersion: DataSemanticsVersion,
        assessedPeriods: [RecordingPeriod],
        issues: [RecordingHistorySelection.Issue],
    ) throws {
        guard !assessedPeriods.isEmpty else { throw ValidationError.emptyAssessment }
        for period in assessedPeriods {
            try period.validate()
        }
        let assessed = RecordingPeriod.union(assessedPeriods)
        let grouped = try RecordingIssue.grouped(issues, version: policyVersion)
        guard grouped.allSatisfy({ issue in
            assessed.contains { $0.start <= issue.period.start && issue.period.end <= $0.end }
        }) else { throw ValidationError.issueOutsideAssessment }
        self.scopeID = scopeID
        self.generationID = generationID
        self.policyVersion = policyVersion
        self.assessedPeriods = assessed
        self.issues = grouped
    }

    func covers(_ periods: [RecordingPeriod]) -> Bool {
        periods.allSatisfy { period in
            assessedPeriods.contains { $0.start <= period.start && period.end <= $0.end }
        }
    }
}
