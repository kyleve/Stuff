import Foundation

/// A proposed edit to one device's eligibility/calendar or one precise place. Its periods are
/// fixed before preview, including the saved end of a temporary ignore and a resume's cutoff.
public enum RecordingControlEdit: Hashable, Sendable {
    public enum ValidationError: Error { case notAnIgnore }

    /// An end-date intent tied to the original ignore. A refreshed preview can include later
    /// extensions of that operation; Apply never widens the already-reviewed proposal.
    public struct IgnoreEnd: Hashable, Sendable {
        public let originalID: RecordingIgnoreDecision.ID
        public let deviceID: RecordingDeviceID
        public let period: RecordingPeriod
        public let until: RecordingIgnoreDecision.Until
    }

    case ignore(
        deviceID: RecordingDeviceID,
        periods: [RecordingPeriod],
        change: RecordingIgnoreDecision.Change,
    )
    case ignoreEnd(IgnoreEnd)
    case place(
        placeID: RecordingPlace.ID,
        periods: [RecordingPeriod],
        action: RecordingPlaceDecision.Action,
    )
    case calendar(
        deviceID: RecordingDeviceID,
        periods: [RecordingPeriod],
        action: RecordingCalendarDecision.Action,
    )

    /// Replace the whole reviewed interval, including eligibility after a shortened end.
    /// The new decision retains its selected day/zone and applies atomically on remote delivery.
    public static func changingIgnoreEnd(
        of decision: RecordingIgnoreDecision,
        until: RecordingIgnoreDecision.Until,
    ) throws -> Self {
        try decision.validate()
        guard case .ignore = decision.change, let period = decision.periods.first
        else { throw ValidationError.notAnIgnore }
        return try .ignoreEnd(.init(
            originalID: decision.id,
            deviceID: decision.deviceID,
            period: .init(start: period.start, end: max(period.end, until.end)),
            until: until,
        ))
    }

    public func query() throws -> RecordingReviewQuery {
        switch self {
            case let .ignore(deviceID, periods, _), let .calendar(deviceID, periods, _):
                try RecordingReviewQuery(periods: periods, deviceIDs: [deviceID])
            case let .ignoreEnd(edit):
                try RecordingReviewQuery(periods: [edit.period], deviceIDs: [edit.deviceID])
            case let .place(_, periods, _):
                try RecordingReviewQuery(periods: periods, deviceIDs: [])
        }
    }

    /// Expand only a new preview of an end-date edit. The causal descendants identify later
    /// extensions of the chosen ignore; independent periods do not broaden its scope.
    func includingObservedIgnoreExtensions(_ controls: RecordingControlSnapshot) throws -> Self {
        guard case let .ignoreEnd(edit) = self else { return self }
        let candidates = controls.ignores.filter { $0.deviceID == edit.deviceID }
        var descendants: Set<RecordingIgnoreDecision.ID> = [edit.originalID]
        var changed = true
        while changed {
            let before = descendants
            for candidate in candidates
                where !candidate.predecessors.isDisjoint(with: descendants)
            {
                descendants.insert(candidate.id)
            }
            changed = before != descendants
        }
        let end = candidates.filter {
            guard descendants.contains($0.id), case .ignore = $0.change else { return false }
            return $0.periods.contains { $0.overlaps(edit.period) }
        }.flatMap(\.periods).map(\.end).max() ?? edit.period.end
        guard end > edit.period.end else { return self }
        return try .ignoreEnd(.init(
            originalID: edit.originalID,
            deviceID: edit.deviceID,
            period: .init(start: edit.period.start, end: end),
            until: edit.until,
        ))
    }

    func prepare(
        operationID: UUID,
        author: RecordingDeviceID,
        evidence: RecordingReviewEvidence,
    ) throws -> RecordingControl {
        let periods = try query().periods
        func overlaps(_ old: [RecordingPeriod]) -> Bool {
            old.contains { oldPeriod in periods.contains { oldPeriod.overlaps($0) } }
        }
        switch self {
            case let .ignoreEnd(edit):
                return try Self.ignore(
                    deviceID: edit.deviceID,
                    periods: [edit.period],
                    change: .ignore(edit.until),
                ).prepare(operationID: operationID, author: author, evidence: evidence)
            case let .ignore(deviceID, _, change):
                return try .ignore(.init(
                    id: .init(rawValue: operationID),
                    author: author,
                    deviceID: deviceID,
                    periods: periods,
                    change: change,
                    predecessors: Set(evidence.controls.ignores.filter {
                        $0.deviceID == deviceID && overlaps($0.periods)
                    }.map(\.id)),
                    version: evidence.policyVersion,
                ))
            case let .place(placeID, _, action):
                return try .place(.init(
                    id: .init(rawValue: operationID),
                    author: author,
                    placeID: placeID,
                    periods: periods,
                    action: action,
                    predecessors: Set(evidence.controls.places.filter {
                        $0.placeID == placeID && overlaps($0.periods)
                    }.map(\.id)),
                    version: evidence.policyVersion,
                ))
            case let .calendar(deviceID, _, action):
                if case let .establish(context) = action {
                    for sample in evidence.samples where sample.source.isGPS
                        && sample.recordingDeviceID == deviceID
                        && periods.contains(where: { $0.contains(sample.timestamp) })
                    {
                        if case let .resolved(recorded) = sample.recordingDay,
                           recorded.secondsFromGMT != context.secondsFromGMT
                        {
                            throw RecordingCalendarContext.ValidationError
                                .conflictingRecordedContext
                        }
                    }
                }
                return try .calendar(.init(
                    id: .init(rawValue: operationID),
                    author: author,
                    deviceID: deviceID,
                    periods: periods,
                    action: action,
                    predecessors: Set(evidence.controls.calendarContexts.filter {
                        $0.deviceID == deviceID && overlaps($0.periods)
                    }.map(\.id)),
                    version: evidence.policyVersion,
                ))
        }
    }
}
