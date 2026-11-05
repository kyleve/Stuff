import Foundation

/// The unresolved history that can affect a report's logical dates. Resolved presence can still
/// contribute on these dates; reminder preferences never change this assessment.
public enum HistoryCompleteness: Hashable, Sendable {
    public enum ValidationError: Error { case outsideAssessedScope }

    case foundation
    case recording(
        version: DataSemanticsVersion,
        days: ClosedRange<CalendarDay>,
        issues: [RecordingHistorySelection.Issue],
    )

    public var policyVersion: DataSemanticsVersion {
        switch self {
            case .foundation: DataCompatibilityPolicy.foundation.current
            case let .recording(version, _, _): version
        }
    }

    public var issues: [RecordingHistorySelection.Issue] {
        switch self {
            case .foundation: []
            case let .recording(_, _, issues): issues
        }
    }

    public var isComplete: Bool {
        issues.isEmpty
    }

    public var affectedDays: Set<CalendarDay> {
        switch self {
            case .foundation: []
            case let .recording(_, days, issues):
                Set(issues.flatMap(\.days.candidates).filter { days.contains($0) })
        }
    }

    public var hasUnassignedDays: Bool {
        issues.contains {
            switch $0.days {
                case .known: false
                case .unassigned: true
            }
        }
    }

    public init(selection: RecordingHistorySelection, days: ClosedRange<CalendarDay>) throws {
        let requested = try LocationHistoryQuery.days(days).recordingPeriod()
        guard RecordingPeriod.union(selection.controls.map(\.period)).contains(where: {
            $0.start <= requested.start && $0.end >= requested.end
        }) else { throw ValidationError.outsideAssessedScope }
        self = try Self.filtered(
            version: selection.policyVersion,
            issues: selection.issues,
            days: days,
        )
    }

    /// Eligibility can narrow an assessed result, but cannot claim coverage beyond that snapshot.
    public func restricted(to days: ClosedRange<CalendarDay>) throws -> Self {
        switch self {
            case .foundation: return .foundation
            case let .recording(version, scope, issues):
                guard scope.lowerBound <= days.lowerBound,
                      scope.upperBound >= days.upperBound
                else {
                    throw ValidationError.outsideAssessedScope
                }
                return try Self.filtered(version: version, issues: issues, days: days)
        }
    }

    private static func filtered(
        version: DataSemanticsVersion,
        issues: [RecordingHistorySelection.Issue],
        days: ClosedRange<CalendarDay>,
    ) throws -> Self {
        let period = try LocationHistoryQuery.days(days).recordingPeriod()
        return .recording(
            version: version,
            days: days,
            issues: issues.compactMap { issue in
                guard let overlap = issue.period.intersection(period) else { return nil }
                if case let .known(candidates) = issue.days,
                   !candidates.contains(where: { days.contains($0) }) { return nil }
                return RecordingHistorySelection.Issue(
                    period: overlap,
                    problem: issue.problem,
                    days: issue.days,
                    sampleIDs: issue.sampleIDs,
                )
            },
        )
    }

    public func requireComplete() throws {
        guard isComplete else { throw UnresolvedHistoryError(completeness: self) }
    }
}

/// A history report cannot be exported or presented as complete until these periods are reviewed.
public struct UnresolvedHistoryError: Error, Sendable {
    public let completeness: HistoryCompleteness
}
