extension ReportReader {
    /// Read all requested periods under one admitted snapshot. Adjacent assessment supplies
    /// current combined context, but the queue retains its narrower original choice periods.
    func recordingReview(
        periods: [RecordingPeriod],
        scopeID: RecordingReviewSnapshot.ScopeID,
    ) async throws -> RecordingReviewSnapshot {
        guard !periods.isEmpty
        else { throw RecordingReviewSnapshot.ValidationError.emptyAssessment }
        for period in periods {
            try period.validate()
        }
        let padding = RecordingEvidencePolicy.evidencePadding
        let assessedPeriods = try RecordingPeriod.union(RecordingPeriod.union(periods).map {
            try RecordingPeriod(
                start: $0.start.addingTimeInterval(-padding),
                end: $0.end.addingTimeInterval(padding),
            )
        })
        return try await Self.logger.measure(.recordingReview, budget: .seconds(2)) {
            try await store.readSnapshot {
                let generation = try await store.dataGeneration()
                let attribution = try await history.attributionSnapshot(attributor)
                var issues: [RecordingHistorySelection.Issue] = []
                var policyVersion: DataSemanticsVersion?
                for period in assessedPeriods {
                    try Task.checkCancellation()
                    let projection = try await history.projection(
                        for: .instants(period),
                        calendar: aggregator.calendar,
                        attributor: attribution,
                    )
                    let current: DataSemanticsVersion
                    switch projection.contract {
                        case .foundation:
                            current = DataCompatibilityPolicy.foundation.current
                        case let .recording(selection):
                            current = selection.policyVersion
                            issues.append(contentsOf: selection.issues)
                    }
                    if let policyVersion, policyVersion != current {
                        throw DataCompatibilityError.concurrentChange
                    }
                    policyVersion = current
                }
                guard let policyVersion
                else { throw RecordingReviewSnapshot.ValidationError.emptyAssessment }
                return try RecordingReviewSnapshot(
                    scopeID: scopeID,
                    generationID: generation.id,
                    policyVersion: policyVersion,
                    assessedPeriods: assessedPeriods,
                    issues: issues,
                )
            }
        }
    }
}
