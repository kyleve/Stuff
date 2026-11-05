/// The exact history scope and named devices used by a control preview. Evidence reads include
/// bounded adjacent context; that expansion never broadens the operation's authored periods.
public struct RecordingReviewQuery: Hashable, Sendable {
    public let periods: [RecordingPeriod]
    public let deviceIDs: Set<RecordingDeviceID>

    public init(periods: [RecordingPeriod], deviceIDs: Set<RecordingDeviceID>) throws {
        guard !periods.isEmpty else { throw DataCompatibilityError.incompleteRecord }
        for period in periods {
            try period.validate()
        }
        self.periods = RecordingPeriod.union(periods)
        self.deviceIDs = deviceIDs
    }

    func evidencePeriods() throws -> [RecordingPeriod] {
        let padding = RecordingEvidencePolicy.maximumObservationGap
            + RecordingEvidencePolicy.contextPadding + RecordingEvidencePolicy.pointSupport
        return try RecordingPeriod.union(periods.map {
            try RecordingPeriod(
                start: $0.start.addingTimeInterval(-padding),
                end: $0.end.addingTimeInterval(padding),
            )
        })
    }
}
