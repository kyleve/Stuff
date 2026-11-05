import Foundation

/// All stored years plus today's year, published from one admitted snapshot. Recording concerns
/// are grouped across annual query boundaries; unknown dates never acquire a fabricated label.
public struct HistoricalDataIssueScanResult: Sendable {
    public struct Revision: Hashable, Sendable {
        let rawValue: UUID
    }

    public struct Year: Sendable {
        public let context: RecordingReviewReference.Context
        public let scan: DataIssueScanResult
    }

    public let revision: Revision
    public let years: [Year]
    public let recording: RecordingReviewSnapshot

    public var issues: [any DataIssue] {
        var seen: Set<DataIssueID> = []
        return years.flatMap(\.scan.issues).filter { seen.insert($0.id).inserted }
    }

    /// Actionable ordinary and recording concerns, deduplicated across historical years.
    /// Confident automatic selections and informational flight reviews do not contribute.
    public var issueCount: Int {
        issues.count + recording.issues.count
    }

    public var reviews: [GPSCorrectionReview] {
        years.flatMap(\.scan.reviews)
    }

    public var nextReassessmentAt: Date? {
        years.compactMap(\.scan.nextReassessmentAt).min()
    }

    #if DEBUG
        /// Synchronous admitted-result fixtures for presentation tests and previews.
        @_spi(Testing) public init(
            yearScans: [Int: DataIssueScanResult],
            calendar: Calendar,
        ) throws {
            guard let version = yearScans.values.first?.completeness.policyVersion else {
                throw RecordingReviewSnapshot.ValidationError.emptyAssessment
            }
            guard yearScans.values.allSatisfy({ $0.completeness.policyVersion == version }) else {
                throw DataCompatibilityError.concurrentChange
            }
            years = try yearScans.sorted { $0.key < $1.key }.map { year, scan in
                try Year(
                    context: .init(
                        historicalYear: year,
                        query: .days(ReportReader.dataIssueContextDays(for: year)),
                    ),
                    scan: scan,
                )
            }
            recording = try RecordingReviewSnapshot(
                scopeID: .init(rawValue: UUID()),
                generationID: .initial,
                policyVersion: version,
                assessedPeriods: years.map {
                    try version.major == 0
                        ? $0.context.query.viewingPeriod(in: calendar)
                        : $0.context.query.recordingPeriod()
                },
                issues: years.flatMap(\.scan.completeness.issues),
            )
            revision = Revision(rawValue: UUID())
        }
    #endif

    init(
        reads: HistoricalDataIssueReads,
        scopeID: RecordingReviewSnapshot.ScopeID,
        assessment: DataIssueAssessment,
        driftThresholdMeters: Double,
        now: Date,
    ) throws {
        var years: [Year] = []
        var periods: [RecordingPeriod] = []
        var issues: [RecordingHistorySelection.Issue] = []
        var version: DataSemanticsVersion?
        for year in reads.years {
            try Task.checkCancellation()
            guard year.reads.dataGenerationID == reads.generationID else {
                throw DataCompatibilityError.concurrentChange
            }
            let current = year.reads.report.completeness.policyVersion
            if let version, version != current { throw DataCompatibilityError.concurrentChange }
            version = current
            // Use the full physical selection, not the report's logical-date filter, to state
            // which absolute periods were assessed and capture review references honestly.
            switch year.reads.history.contract {
                case .foundation:
                    guard current == DataCompatibilityPolicy.foundation.current else {
                        throw DataCompatibilityError.concurrentChange
                    }
                    try periods.append(year.context.query.viewingPeriod(in: assessment.calendar))
                case let .recording(selection):
                    guard selection.policyVersion == current else {
                        throw DataCompatibilityError.concurrentChange
                    }
                    let period = try year.context.query.recordingPeriod()
                    guard RecordingPeriod.union(selection.controls.map(\.period)).contains(where: {
                        $0.start <= period.start && period.end <= $0.end
                    }) else { throw HistoryCompleteness.ValidationError.outsideAssessedScope }
                    periods.append(period)
                    issues.append(contentsOf: selection.issues)
            }
            try years.append(Year(
                context: year.context,
                scan: assessment.scan(
                    reads: year.reads,
                    driftThresholdMeters: driftThresholdMeters,
                    now: now,
                ),
            ))
        }
        guard let version else { throw RecordingReviewSnapshot.ValidationError.emptyAssessment }
        recording = try RecordingReviewSnapshot(
            scopeID: scopeID,
            generationID: reads.generationID,
            policyVersion: version,
            assessedPeriods: periods,
            issues: issues,
        )
        revision = Revision(rawValue: UUID())
        self.years = years
    }

    /// Capture the original year/query alongside each bounded period. Overlapping annual
    /// contexts remain separate references; RecordingReviewQueue reviews their shared work once.
    public func references(for issue: RecordingIssue) throws -> Set<RecordingReviewReference> {
        guard recording.issues.contains(issue) else {
            throw RecordingReviewReference.ValidationError.unknownIssue
        }
        return try Set(years.compactMap { year in
            guard let overlap = try issue.period.intersection(year.context.query.recordingPeriod())
            else { return nil }
            return try RecordingReviewReference(
                issue: issue,
                originalPeriods: [overlap],
                context: year.context,
                snapshot: recording,
            )
        })
    }
}
