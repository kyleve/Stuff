import Foundation
import RegionKit

/// Read-only comparisons for the exact proposal the user can save. Contributions describe only
/// the reviewed periods; unrelated observations and manual days can still contribute to totals.
public enum RecordingChoiceInspection: Hashable, Sendable {
    public struct Track: Hashable, Sendable, Identifiable {
        public var id: RecordingDeviceID {
            deviceID
        }

        public let deviceID: RecordingDeviceID
        public let observations: [RecordingObservation]
        public let availablePeriods: [RecordingPeriod]
        public let gaps: [RecordingPeriod]
    }

    public struct History: Hashable, Sendable {
        public let selections: [RecordingHistorySelection]
        public let contributions: [DayPresence]
        public let issues: [RecordingIssue]

        init(selections: [RecordingHistorySelection], version: DataSemanticsVersion) throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            // Every entry retains its recording CalendarDay; this calendar cannot rebucket it.
            // The shared aggregator also preserves recorded transit days with no region presence.
            contributions = try DayAggregator(calendar: calendar, timeZone: .gmt).aggregate(
                history: selections.flatMap { try $0.attributedSamples() },
            )
            issues = try RecordingIssue.grouped(selections.flatMap(\.issues), version: version)
            self.selections = selections
        }
    }

    public struct Preview: Hashable, Sendable {
        public let proposal: RecordingChoiceReview.Proposal
        public let tracks: [Track]
        public let before: History
        public let after: History
    }

    case ready(Preview)
    case needsCalendarContext(RecordingChoiceReview.Clarification)
    case absentRecordingDay(RecordingChoiceRequest)

    init(
        proposal: RecordingChoiceReview.Proposal,
        catalog: any RegionAttributing,
        policy: DataCompatibilityPolicy,
    ) throws {
        let evidence = proposal.evidence
        let periods = RecordingPeriod.union(proposal.decision.periods)
        let observations = try RecordingObservation.history(
            samples: evidence.samples.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id.uuidString < $1.id.uuidString
            },
            corrections: Array(evidence.corrections),
            controls: evidence.controls,
            catalog: catalog,
            version: evidence.policyVersion,
        )
        let updated = try RecordingControlSnapshot(
            records: evidence.controls.records + [RecordingControlCodec.encode(
                .source(proposal.decision),
                generationID: evidence.generationID,
            )],
            generationID: evidence.generationID,
            policy: policy,
        )
        func history(controls: RecordingControlSnapshot) throws -> History {
            try History(selections: periods.map {
                try RecordingHistorySelection.resolve(
                    observations: observations,
                    controls: controls,
                    removals: Array(evidence.removals),
                    within: $0,
                    version: evidence.policyVersion,
                )
            }, version: evidence.policyVersion)
        }
        let visible = Set(RecordingDeviceRemovalFilter.visibleSamples(
            observations.map(\.sample),
            removals: Array(evidence.removals),
        ).map(\.id))
        var deviceIDs = Set(observations.map(\.deviceID))
        deviceIDs.formUnion(evidence.query.deviceIDs)
        for choice in evidence.controls.sourceChoices {
            if case let .select(deviceID) = choice.action { deviceIDs.insert(deviceID) }
        }
        let tracks = try deviceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.map {
            deviceID in
            let recorded = observations.filter { $0.deviceID == deviceID }
            let coverage = try MultiDeviceAssessment.coverage(recorded.filter {
                visible.contains($0.sample.id)
            })
            let available = RecordingPeriod.union(periods.flatMap { period in
                coverage.compactMap { $0.intersection(period) }
            })
            return try Track(
                deviceID: deviceID,
                observations: recorded,
                availablePeriods: available,
                gaps: Self.gaps(in: periods, coveredBy: available),
            )
        }
        self = try .ready(.init(
            proposal: proposal,
            tracks: tracks,
            before: history(controls: evidence.controls),
            after: history(controls: updated),
        ))
    }

    private static func gaps(
        in periods: [RecordingPeriod],
        coveredBy coverage: [RecordingPeriod],
    ) throws -> [RecordingPeriod] {
        var gaps: [RecordingPeriod] = []
        for period in periods {
            var cursor = period.start
            for covered in coverage.compactMap({ $0.intersection(period) }) {
                if cursor < covered.start {
                    try gaps.append(.init(start: cursor, end: covered.start))
                }
                cursor = covered.end
            }
            if cursor < period.end { try gaps.append(.init(start: cursor, end: period.end)) }
        }
        return gaps
    }
}
