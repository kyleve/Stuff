import Foundation
import RegionKit

/// Pure, bounded assessment of competing GPS tracks. This foundation does not read or write a
/// store and is not connected to production history. Durable controls are resolved separately.
public enum MultiDeviceAssessment {
    public enum Selection: Hashable, Sendable {
        case noEvidence
        case onlyAvailableDevice(RecordingDeviceID)
        case agreement(Set<RecordingDeviceID>)
        case movingOverStationary(RecordingDeviceID)
        case conflict(Set<RecordingDeviceID>)
        case uncertain(Set<RecordingDeviceID>)
    }

    public struct Track: Hashable, Sendable {
        public let deviceID: RecordingDeviceID
        public let geography: RecordingGeography?
        public var region: Region? {
            geography?.singleRegion
        }

        public let recordingDay: CalendarDay?
        public let bracketingObservations: [RecordingObservation]
        /// Spatial corroboration can retain a prior anchor without replacing the final fix's
        /// effective corrected geography or authoritative recorded day.
        public let divergenceObservations: [RecordingObservation]
        public let evidence: RecordingTrackAssessment
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let selection: Selection
        public let tracks: [Track]
        public let policyVersion: DataSemanticsVersion
    }

    public enum ValidationError: Error {
        case conflictingSampleIdentity(UUID)
    }

    private struct DeviceTrack {
        let deviceID: RecordingDeviceID
        let index: RecordingObservationIndex
        let coverage: [RecordingPeriod]

        func coverage(at instant: Date) -> RecordingPeriod? {
            // Unioned coverage is disjoint and sorted by both start and end.
            var lower = 0
            var upper = coverage.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if coverage[middle].end <= instant { lower = middle + 1 }
                else { upper = middle }
            }
            guard lower < coverage.count, coverage[lower].contains(instant) else { return nil }
            return coverage[lower]
        }
    }

    public static func assess(
        observations: [RecordingObservation],
        within query: RecordingPeriod,
        places: [RecordingPlace],
    ) throws -> [Segment] {
        try query.validate()
        for place in places {
            try place.validate()
        }
        var unique: [UUID: RecordingObservation] = [:]
        for observation in observations {
            if let existing = unique[observation.sample.id], existing != observation {
                throw ValidationError.conflictingSampleIdentity(observation.sample.id)
            }
            unique[observation.sample.id] = observation
        }
        let grouped = Dictionary(grouping: unique.values, by: \.deviceID)
        let deviceTracks = try grouped.keys
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            .map { deviceID in
                let index = RecordingObservationIndex(grouped[deviceID] ?? [])
                return try DeviceTrack(
                    deviceID: deviceID,
                    index: index,
                    coverage: coverage(index.observations),
                )
            }
        let endpoints = deviceTracks.flatMap { track in
            track.coverage.flatMap { [$0.start, $0.end] }
                + track.index.observations.map(\.sample.timestamp)
        }
        // Assess the evidence's own intervals before clipping to the requested period. A report
        // boundary must not move an evidence window and change the selection at the same instant.
        let boundaries = Set(endpoints).sorted()
        guard let first = boundaries.first, let last = boundaries.last else {
            return [Segment(
                period: query,
                selection: .noEvidence,
                tracks: [],
                policyVersion: RecordingEvidencePolicy.version,
            )]
        }
        var result: [Segment] = []
        if query.start < first {
            try result.append(Segment(
                period: RecordingPeriod(start: query.start, end: min(first, query.end)),
                selection: .noEvidence,
                tracks: [],
                policyVersion: RecordingEvidencePolicy.version,
            ))
        }
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let boundary = try RecordingPeriod(start: start, end: end)
            guard let period = boundary.intersection(query)
            else { continue }
            let tracks = try deviceTracks.compactMap { track throws -> Track? in
                guard let component = track.coverage(at: start)
                else { return nil }
                let context = track.index.context(
                    in: component,
                    around: boundary,
                    padding: RecordingEvidencePolicy.contextPadding,
                )
                let before = context.last { $0.sample.timestamp <= start }?.sample.timestamp
                let after = context.first { $0.sample.timestamp > start }?.sample.timestamp
                // The final point still has its bounded one-second support. Retain the preceding
                // anchor when there is no following point, so that tail cannot suddenly combine
                // tracks that were demonstrably divergent up to the very same observation.
                let trailingAnchor = after == nil
                    ? before
                    .flatMap { last in
                        context.last { $0.sample.timestamp < last }?.sample.timestamp
                    } : nil
                // Different observations can share a timestamp. Retain all of them so UUID
                // ordering cannot hide contradictory region or recording-day assignments.
                let brackets = context.filter {
                    $0.sample.timestamp == before || $0.sample.timestamp == after
                }
                let divergence = context.filter {
                    $0.sample.timestamp == before || $0.sample.timestamp == after
                        || $0.sample.timestamp == trailingAnchor
                }
                let geography = brackets.first?.geography
                let day = brackets.first?.recordingDay.day
                return try Track(
                    deviceID: track.deviceID,
                    geography: brackets.allSatisfy { $0.geography == geography } ? geography : nil,
                    recordingDay: brackets.allSatisfy { $0.recordingDay.day == day } ? day : nil,
                    bracketingObservations: brackets,
                    divergenceObservations: divergence,
                    evidence: RecordingTrackAssessment.assess(
                        observations: context,
                        places: places,
                    ),
                )
            }
            result.append(Segment(
                period: period,
                selection: selection(tracks, at: start),
                tracks: tracks,
                policyVersion: RecordingEvidencePolicy.version,
            ))
        }
        if query.end > last {
            try result.append(Segment(
                period: RecordingPeriod(start: max(last, query.start), end: query.end),
                selection: .noEvidence,
                tracks: [],
                policyVersion: RecordingEvidencePolicy.version,
            ))
        }
        return result
    }

    static func coverage(_ observations: [RecordingObservation]) throws
        -> [RecordingPeriod]
    {
        var periods = try observations.map { observation in
            try RecordingPeriod(
                start: observation.sample.timestamp,
                end: observation.sample.timestamp
                    .addingTimeInterval(RecordingEvidencePolicy.pointSupport),
            )
        }
        for (left, right) in zip(observations, observations.dropFirst()) {
            let gap = right.sample.timestamp.timeIntervalSince(left.sample.timestamp)
            if gap > 0, gap <= RecordingEvidencePolicy.maximumObservationGap {
                try periods.append(RecordingPeriod(
                    start: left.sample.timestamp,
                    end: right.sample.timestamp
                        .addingTimeInterval(RecordingEvidencePolicy.pointSupport),
                ))
            }
        }
        return RecordingPeriod.union(periods)
    }

    private static func selection(_ tracks: [Track], at instant: Date) -> Selection {
        guard let first = tracks.first else { return .noEvidence }
        guard tracks.count > 1 else { return .onlyAvailableDevice(first.deviceID) }
        let devices = Set(tracks.map(\.deviceID))
        if let geography = first.geography, geography.establishesAgreement,
           let day = first.recordingDay,
           tracks.allSatisfy({ $0.geography == geography && $0.recordingDay == day })
        { return .agreement(devices) }

        // A bracket can span midnight and therefore have no single day. Its observation at
        // this exact evidence boundary still has an authoritative label; do not let the nil
        // summary conceal disagreement between simultaneous fixes on different logical days.
        let observedDays = tracks.flatMap(\.bracketingObservations)
            .filter { $0.sample.timestamp == instant }.compactMap(\.recordingDay.day)
        let knownDays = Set(tracks.compactMap(\.recordingDay)).union(observedDays)
        let divergent = tracks.enumerated().contains { index, left in
            tracks.dropFirst(index + 1).contains { right in
                hasRepeatedPositions(left) && hasRepeatedPositions(right)
                    && left.divergenceObservations.allSatisfy { leftObservation in
                        right.divergenceObservations.allSatisfy { rightObservation in
                            leftObservation.sample.coordinate
                                .distance(to: rightObservation.sample.coordinate)
                                - leftObservation.sample.horizontalAccuracy - rightObservation
                                .sample.horizontalAccuracy
                                > RecordingEvidencePolicy.divergentTrackDistanceMeters
                        }
                    }
            }
        }
        // Equal unresolved geography is neither agreement nor a conflict by itself.
        // Different region labels near a boundary, or one isolated distant fix, do not establish
        // a geographic conflict. Retain their uncertainty instead of claiming agreement.
        guard knownDays.count > 1 || divergent else {
            return .uncertain(devices)
        }
        let moving = tracks.filter { $0.evidence.activity == .moving }
        if moving.count == 1, let winner = moving.first,
           tracks.filter({ $0.deviceID != winner.deviceID })
           .allSatisfy({ $0.evidence.activity == .stationary })
        { return .movingOverStationary(winner.deviceID) }
        return .conflict(devices)
    }

    private static func hasRepeatedPositions(_ track: Track) -> Bool {
        guard let first = track.divergenceObservations.first,
              let last = track.divergenceObservations.last,
              last.sample.timestamp.timeIntervalSince(first.sample.timestamp)
              >= RecordingEvidencePolicy.minimumAnchorInterval
        else { return false }
        return track.divergenceObservations.allSatisfy {
            $0.sample.horizontalAccuracy <= RecordingEvidencePolicy.maximumAccuracyMeters
        }
    }
}
