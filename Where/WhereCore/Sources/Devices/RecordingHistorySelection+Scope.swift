import Foundation

extension RecordingHistorySelection {
    /// Restrict an already assessed result without inventing coverage or re-running selection
    /// from truncated observations. Reviewed correction equality retains only this context.
    func clipped(to period: RecordingPeriod) throws -> Self {
        try Self(
            contributions: contributions.filter { period.contains($0.sample.timestamp) },
            segments: segments.compactMap { segment in
                segment.period.intersection(period).map { .init(
                    period: $0,
                    resolution: segment.resolution,
                ) }
            },
            issues: issues.compactMap { issue in
                issue.period.intersection(period).map {
                    .init(
                        period: $0,
                        problem: issue.problem,
                        days: issue.days,
                        sampleIDs: issue.sampleIDs,
                    )
                }
            },
            policyVersion: policyVersion,
            evidence: evidence.clipped(to: period),
        )
    }
}
