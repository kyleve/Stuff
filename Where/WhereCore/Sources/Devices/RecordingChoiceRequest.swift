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

    func query() throws -> RecordingReviewQuery {
        var devices: Set<RecordingDeviceID> = []
        if case let .select(deviceID) = action { devices.insert(deviceID) }
        if case let .recordingDay(deviceID, _) = scope { devices.insert(deviceID) }
        return try RecordingReviewQuery(periods: searchPeriods(), deviceIDs: devices)
    }

    func evidencePeriods() throws -> [RecordingPeriod] {
        try query().evidencePeriods()
    }
}
