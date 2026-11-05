/// Retains missing or conflicting calendar coverage explicitly. Only positive, agreed context
/// can assign a day or fill a whole-day source choice's GPS gaps.
public enum RecordingCalendarResolver {
    /// User-established context can resolve an unknown assignment without rewriting the raw
    /// observation. A recorded assignment remains authoritative over later calendar controls.
    public static func assignment(
        for sample: LocationSample,
        decisions: [RecordingCalendarDecision],
        version: DataSemanticsVersion,
    ) throws -> RecordingDayAssignment {
        try sample.validateRecordingContract()
        guard let assignment = sample.recordingDay, let deviceID = sample.recordingDeviceID else {
            throw RecordingObservation.ValidationError.unattributedGPS
        }
        switch assignment {
            case .resolved: return assignment
            case .unresolved:
                let point = try RecordingPeriod(
                    start: sample.timestamp,
                    end: sample.timestamp.addingTimeInterval(RecordingEvidencePolicy.pointSupport),
                )
                let segments = try resolve(
                    decisions,
                    for: deviceID,
                    within: point,
                    version: version,
                )
                if let segment = segments.first(where: { $0.period.contains(sample.timestamp) }),
                   case let .established(context) = segment.resolution
                {
                    return try .resolved(.init(
                        observedAt: sample.timestamp,
                        calendarContext: context,
                    ))
                }
                return .unresolved
        }
    }

    public enum Resolution: Hashable, Sendable {
        case unknown
        case established(RecordingCalendarContext)
        case conflict(Set<RecordingCalendarDecision.ID>)
        case incomplete(Set<RecordingCalendarDecision.ID>)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let resolution: Resolution
        public let effectiveDecisions: Set<RecordingCalendarDecision.ID>
    }

    public enum ValidationError: Error, Equatable {
        case conflictingIdentity(RecordingCalendarDecision.ID)
        case invalidPredecessor(RecordingCalendarDecision.ID)
        case unsupportedMajor(RecordingCalendarDecision.ID)
    }

    public static func resolve(
        _ decisions: [RecordingCalendarDecision],
        for deviceID: RecordingDeviceID,
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        var records: [RecordingCalendarDecision.ID: RecordingCalendarDecision] = [:]
        for decision in decisions {
            if let old = records[decision.id],
               old != decision { throw ValidationError.conflictingIdentity(decision.id) }
            records[decision.id] = decision
        }
        let relevant = decisions.filter { $0.deviceID == deviceID }
        for decision in relevant {
            try decision.validate()
            guard decision.version.major == version.major
            else { throw ValidationError.unsupportedMajor(decision.id) }
            for predecessor in decision.predecessors {
                if let record = records[predecessor], record.deviceID != deviceID {
                    throw ValidationError.invalidPredecessor(decision.id)
                }
            }
        }
        return try CausalPeriodResolver<RecordingCalendarDecision>.resolve(relevant, within: query)
            .map { segment in
                let resolution: Resolution = switch segment.resolution {
                    case .absent, .agreed(.withdraw): .unknown
                    case let .agreed(.establish(context)): .established(context)
                    case let .conflict(identities): .conflict(identities)
                    case let .incomplete(identities): .incomplete(identities)
                }
                return Segment(
                    period: segment.period,
                    resolution: resolution,
                    effectiveDecisions: segment.effectiveOperations,
                )
            }
    }
}
