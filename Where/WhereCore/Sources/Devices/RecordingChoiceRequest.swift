import Foundation

/// The exact source action and scope presented for review. A logical day has no guessed UTC
/// bounds: its complete calendar context must establish the periods before a proposal exists.
public struct RecordingChoiceRequest: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case periods([RecordingPeriod])
        case recordingDay(deviceID: RecordingDeviceID, day: CalendarDay)
    }

    public let scope: Scope
    public let action: HistoryDecision.Action

    public init(scope: Scope, action: HistoryDecision.Action) {
        self.scope = scope
        self.action = action
    }

    func searchPeriods() throws -> [RecordingPeriod] {
        switch scope {
            case let .periods(periods):
                guard !periods.isEmpty else { throw DataCompatibilityError.incompleteRecord }
                for period in periods {
                    try period.validate()
                }
                return RecordingPeriod.union(periods)
            case let .recordingDay(deviceID, day):
                if case let .select(selected) = action, selected != deviceID {
                    throw DataCompatibilityError.conflictingRecord
                }
                return try [RecordingDayCoverage.searchPeriod(for: day)]
        }
    }

    /// Keep enough adjacent evidence for the bounded assessment to retain its original
    /// intervals and movement context. Query clipping must not change the reviewed result.
    func evidencePeriods() throws -> [RecordingPeriod] {
        let padding = RecordingEvidencePolicy.maximumObservationGap
            + RecordingEvidencePolicy.contextPadding + RecordingEvidencePolicy.pointSupport
        return try RecordingPeriod.union(searchPeriods().map {
            try RecordingPeriod(
                start: $0.start.addingTimeInterval(-padding),
                end: $0.end.addingTimeInterval(padding),
            )
        })
    }
}
