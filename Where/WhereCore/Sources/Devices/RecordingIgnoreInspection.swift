import Foundation

/// Compares the displayed ignore proposal with its reviewed controls. Explicit sources,
/// removals, and unknown controls keep the same precedence as production history selection.
public struct RecordingIgnoreInspection: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case automatic(RecordingControlSelection.Eligibility)
        case selected(RecordingDeviceID)
        case unresolved(RecordingControlSelection.Problem)
    }

    public struct Change: Hashable, Sendable {
        public let period: RecordingPeriod
        public let before: Outcome
        public let after: Outcome
    }

    public enum ValidationError: Error, Equatable { case notAnIgnore, multipleDevices }

    public let deviceID: RecordingDeviceID
    public let changes: [Change]

    init(
        proposal: RecordingControlEditCoordinator.Proposal,
        policy: DataCompatibilityPolicy,
    ) throws {
        let ignores = proposal.edits.compactMap { prepared -> RecordingIgnoreDecision? in
            if case let .ignore(decision) = prepared.control { return decision }
            return nil
        }
        guard let first = ignores.first,
              ignores.count == proposal.edits.count
        else { throw ValidationError.notAnIgnore }
        guard ignores.allSatisfy({ $0.deviceID == first.deviceID })
        else { throw ValidationError.multipleDevices }
        deviceID = first.deviceID
        let evidence = proposal.evidence
        let records = try proposal.edits.map {
            try RecordingControlCodec.encode($0.control, generationID: evidence.generationID)
        }
        let after = try RecordingControlSnapshot(
            records: evidence.controls.records + records,
            generationID: evidence.generationID,
            policy: policy,
        )
        var changes: [Change] = []
        for period in evidence.query.periods {
            let beforeSegments = try RecordingControlSelection.resolve(
                controls: evidence.controls,
                removals: Array(evidence.removals),
                within: period,
                version: evidence.policyVersion,
            )
            let afterSegments = try RecordingControlSelection.resolve(
                controls: after,
                removals: Array(evidence.removals),
                within: period,
                version: evidence.policyVersion,
            )
            let boundaries = Set((beforeSegments + afterSegments).flatMap {
                [$0.period.start, $0.period.end]
            }).sorted()
            for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                guard let before = beforeSegments.first(where: { $0.period.contains(start) }),
                      let after = afterSegments.first(where: { $0.period.contains(start) })
                else { preconditionFailure("Control selection must cover the reviewed period.") }
                try changes.append(Change(
                    period: .init(start: start, end: end),
                    before: Self.outcome(before.resolution, for: first.deviceID),
                    after: Self.outcome(after.resolution, for: first.deviceID),
                ))
            }
        }
        self.changes = changes
    }

    private static func outcome(
        _ resolution: RecordingControlSelection.Resolution,
        for deviceID: RecordingDeviceID,
    ) -> Outcome {
        switch resolution {
            case let .automatic(automatic): .automatic(automatic.eligibility(of: deviceID))
            case let .selected(deviceID): .selected(deviceID)
            case let .unresolved(problem): .unresolved(problem)
        }
    }
}
