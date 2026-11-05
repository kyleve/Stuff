import Foundation

/// One pure selection of GPS history. Inputs retain full-catalog corrections and resolved
/// calendar context. Contributions exclude disputed evidence without changing the raw samples.
public struct RecordingHistorySelection: Hashable, Sendable {
    public enum Problem: Hashable, Sendable {
        case controls(RecordingControlSelection.Problem)
        case eligibility([RecordingDeviceID: RecordingControlSelection.Eligibility])
        case competingTracks(Set<RecordingDeviceID>)
        case recordingDay(Set<RecordingDeviceID>)
    }

    public enum Days: Hashable, Sendable {
        case known(Set<CalendarDay>)
        case unassigned(known: Set<CalendarDay>)

        public var candidates: Set<CalendarDay> {
            switch self {
                case let .known(days), let .unassigned(days): days
            }
        }
    }

    public struct Issue: Hashable, Sendable {
        public let period: RecordingPeriod
        public let problem: Problem
        public let days: Days
        public let sampleIDs: Set<UUID>
    }

    public enum Resolution: Hashable, Sendable {
        case chosen(RecordingDeviceID)
        case automatic(MultiDeviceAssessment.Selection)
        case unresolved(Problem)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let resolution: Resolution
    }

    public enum ValidationError: Error { case unsupportedPolicy }

    public let contributions: [RecordingObservation]
    public let segments: [Segment]
    public let issues: [Issue]
    public let policyVersion: DataSemanticsVersion

    public static func resolve(
        observations: [RecordingObservation],
        controls: RecordingControlSnapshot,
        removals: [RecordingDeviceRemoval],
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> Self {
        guard version == RecordingEvidencePolicy.version
        else { throw ValidationError.unsupportedPolicy }
        var unique: [UUID: RecordingObservation] = [:]
        for observation in observations {
            if let previous = unique[observation.sample.id], previous != observation {
                throw MultiDeviceAssessment.ValidationError
                    .conflictingSampleIdentity(observation.sample.id)
            }
            unique[observation.sample.id] = observation
        }
        let ordered = unique.values.sorted {
            if $0.sample.timestamp != $1.sample
                .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
        let controlSegments = try RecordingControlSelection.resolve(
            controls: controls,
            removals: removals,
            within: query,
            version: version,
        )
        let retainedIDs = Set(RecordingDeviceRemovalFilter.visibleSamples(
            ordered.map(\.sample),
            removals: removals,
        ).map(\.id))
        let retained = ordered.filter { retainedIDs.contains($0.sample.id) }
        let places = try resolvedPlaces(
            controls: controls,
            observations: retained,
            query: query,
            version: version,
        )
        var builder = Builder()
        for control in controlSegments {
            switch control.resolution {
                case let .unresolved(problem):
                    // Keep the same bounded adjacent evidence as automatic conflicts. Clipping
                    // a query must not erase an unresolved control's known dates or provenance.
                    for assessment in try MultiDeviceAssessment.assess(
                        observations: ordered,
                        within: control.period,
                        places: places,
                    ) {
                        builder.unresolved(
                            .controls(problem),
                            within: assessment.period,
                            observations: assessment.tracks.flatMap(\.bracketingObservations),
                            declaredDays: declaredDays(for: control, controls: controls),
                        )
                    }
                case let .selected(deviceID):
                    builder.segments.append(Segment(
                        period: control.period,
                        resolution: .chosen(deviceID),
                    ))
                    // A source choice stays exclusive even when its selected device has no fix.
                    try builder.include(retained.filter {
                        $0.deviceID == deviceID && control.period.contains($0.sample.timestamp)
                    }, within: control.period)
                case let .automatic(automatic):
                    let eligible = retained.filter {
                        switch automatic.eligibility(of: $0.deviceID) {
                            case .eligible, .conflict, .incomplete: true
                            case .ignored, .removed: false
                        }
                    }
                    for assessment in try MultiDeviceAssessment.assess(
                        observations: eligible,
                        within: control.period,
                        places: places,
                    ) {
                        try builder.include(
                            assessment,
                            eligibility: automatic,
                            observations: eligible,
                        )
                    }
            }
        }
        return Self(
            contributions: ordered.filter { builder.contributingIDs.contains($0.sample.id) },
            segments: builder.segments,
            issues: builder.issues,
            policyVersion: version,
        )
    }

    private static func resolvedPlaces(
        controls: RecordingControlSnapshot,
        observations: [RecordingObservation],
        query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [RecordingPlace] {
        let context = try RecordingPeriod(
            start: min(query.start, observations.first?.sample.timestamp ?? query.start),
            end: max(
                query.end,
                (observations.last?.sample.timestamp ?? query.end)
                    .addingTimeInterval(RecordingEvidencePolicy.pointSupport),
            ),
        )
        return try Set(controls.places.map(\.placeID)).sorted().flatMap { placeID in
            try RecordingPlaceResolver.resolve(
                controls.places,
                for: placeID,
                within: context,
                version: version,
            )
            .compactMap { segment in
                switch segment.resolution {
                    case let .place(place): place
                    case .absent, .conflict, .incomplete: nil
                }
            }
        }
    }

    private static func declaredDays(
        for segment: RecordingControlSelection.Segment,
        controls: RecordingControlSnapshot,
    ) -> Days {
        let choices = controls.sourceChoices.filter { segment.sourceChoiceIDs.contains($0.id) }
        var known: Set<CalendarDay> = []
        var complete = !choices.isEmpty && choices.count == segment.sourceChoiceIDs.count
        for choice in choices {
            switch choice.scope {
                case .fixedPeriods: complete = false
                case let .recordingDay(_, day): known.insert(day)
            }
        }
        switch segment.resolution {
            case .unresolved(.missingSourceChoices), .unresolved(.unknownControls): complete = false
            case .automatic, .selected, .unresolved(.sourceConflict),
                 .unresolved(.selectedDeviceRemoved): break
        }
        return complete ? .known(known) : .unassigned(known: known)
    }

    private struct Builder {
        var contributingIDs: Set<UUID> = []
        var segments: [Segment] = []
        var issues: [Issue] = []

        mutating func unresolved(
            _ problem: Problem,
            within period: RecordingPeriod,
            observations: [RecordingObservation],
            declaredDays: Days,
        ) {
            segments.append(Segment(period: period, resolution: .unresolved(problem)))
            issue(problem, within: period, observations: observations, declaredDays: declaredDays)
        }

        mutating func issue(
            _ problem: Problem,
            within period: RecordingPeriod,
            observations: [RecordingObservation],
            declaredDays: Days,
        ) {
            let known = Set(observations.compactMap(\.recordingDay.day))
                .union(declaredDays.candidates)
            let days: Days = if observations.isEmpty {
                // Whole-day choices preserve their logical scope across later GPS gaps.
                declaredDays
            } else if observations.contains(where: { $0.recordingDay.day == nil }) {
                // A choice's scope cannot supply a missing raw observation assignment.
                .unassigned(known: known)
            } else {
                .known(known)
            }
            issues.append(Issue(
                period: period,
                problem: problem,
                days: days,
                sampleIDs: Set(observations.map(\.sample.id)),
            ))
        }

        mutating func include(
            _ observations: [RecordingObservation],
            within period: RecordingPeriod,
        ) throws {
            for observation in observations {
                if observation.recordingDay.day != nil {
                    contributingIDs.insert(observation.sample.id)
                } else {
                    let point = try RecordingPeriod(
                        start: observation.sample.timestamp,
                        end: min(
                            period.end,
                            observation.sample.timestamp
                                .addingTimeInterval(RecordingEvidencePolicy.pointSupport),
                        ),
                    )
                    issue(
                        .recordingDay([observation.deviceID]),
                        within: point,
                        observations: [observation],
                        declaredDays: .unassigned(known: []),
                    )
                }
            }
        }

        mutating func include(
            _ assessment: MultiDeviceAssessment.Segment,
            eligibility: RecordingControlSelection.Automatic,
            observations: [RecordingObservation],
        ) throws {
            let brackets = assessment.tracks.flatMap(\.bracketingObservations)
            var ambiguous: [RecordingDeviceID: RecordingControlSelection.Eligibility] = [:]
            for track in assessment.tracks {
                switch eligibility.eligibility(of: track.deviceID) {
                    case .conflict, .incomplete:
                        ambiguous[track.deviceID] = eligibility.eligibility(of: track.deviceID)
                    case .eligible, .ignored, .removed: break
                }
            }
            guard ambiguous.isEmpty else {
                unresolved(
                    .eligibility(ambiguous),
                    within: assessment.period,
                    observations: brackets,
                    declaredDays: .unassigned(known: []),
                )
                return
            }
            let selected: Set<RecordingDeviceID>
            switch assessment.selection {
                case .noEvidence: selected = []
                case let .onlyAvailableDevice(deviceID),
                     let .movingOverStationary(deviceID): selected = [deviceID]
                case let .agreement(deviceIDs): selected = deviceIDs
                case let .conflict(deviceIDs):
                    unresolved(
                        .competingTracks(deviceIDs),
                        within: assessment.period,
                        observations: brackets,
                        declaredDays: .unassigned(known: []),
                    )
                    return
                case let .uncertain(deviceIDs):
                    // Geography uncertainty alone is not a source conflict. Missing calendar
                    // context cannot silently promote a competing device into a known-day winner.
                    if brackets.contains(where: { $0.recordingDay.day == nil }) {
                        unresolved(
                            .recordingDay(deviceIDs),
                            within: assessment.period,
                            observations: brackets,
                            declaredDays: .unassigned(known: []),
                        )
                        return
                    }
                    selected = deviceIDs
            }
            segments.append(Segment(
                period: assessment.period,
                resolution: .automatic(assessment.selection),
            ))
            try include(observations.filter {
                selected.contains($0.deviceID) && assessment.period.contains($0.sample.timestamp)
            }, within: assessment.period)
        }
    }
}
