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
        public let region: Region?
        public let recordingDay: CalendarDay?
        public let bracketingObservations: [RecordingObservation]
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
        let observations: [RecordingObservation]
        let coverage: [RecordingPeriod]
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
                let ordered = (grouped[deviceID] ?? []).sorted {
                    if $0.sample.timestamp != $1.sample
                        .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
                    return $0.sample.id.uuidString < $1.sample.id.uuidString
                }
                return try DeviceTrack(
                    deviceID: deviceID,
                    observations: ordered,
                    coverage: coverage(ordered),
                )
            }
        let endpoints = deviceTracks.flatMap { track in
            track.coverage.flatMap { [$0.start, $0.end] }
                + track.observations.map(\.sample.timestamp)
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
            guard let period = try RecordingPeriod(start: start, end: end).intersection(query)
            else { continue }
            let tracks = try deviceTracks.compactMap { track throws -> Track? in
                guard let component = track.coverage.first(where: { $0.contains(start) })
                else { return nil }
                let context = track.observations.filter { observation in
                    component.contains(observation.sample.timestamp)
                        && observation.sample.timestamp >= start
                        .addingTimeInterval(-RecordingEvidencePolicy.contextPadding)
                        && observation.sample.timestamp <= end
                        .addingTimeInterval(RecordingEvidencePolicy.contextPadding)
                }
                let before = context.last { $0.sample.timestamp <= start }?.sample.timestamp
                let after = context.first { $0.sample.timestamp > start }?.sample.timestamp
                // Different observations can share a timestamp. Retain all of them so UUID
                // ordering cannot hide contradictory region or recording-day assignments.
                let brackets = context.filter {
                    $0.sample.timestamp == before || $0.sample.timestamp == after
                }
                let region = brackets.first?.region
                let day = brackets.first?.recordingDay.day
                return try Track(
                    deviceID: track.deviceID,
                    region: brackets.allSatisfy { $0.region == region } ? region : nil,
                    recordingDay: brackets.allSatisfy { $0.recordingDay.day == day } ? day : nil,
                    bracketingObservations: brackets,
                    evidence: RecordingTrackAssessment.assess(
                        observations: context,
                        places: places,
                    ),
                )
            }
            result.append(Segment(
                period: period,
                selection: selection(tracks),
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

    private static func coverage(_ observations: [RecordingObservation]) throws
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

    private static func selection(_ tracks: [Track]) -> Selection {
        guard let first = tracks.first else { return .noEvidence }
        guard tracks.count > 1 else { return .onlyAvailableDevice(first.deviceID) }
        let devices = Set(tracks.map(\.deviceID))
        if let region = first.region, let day = first.recordingDay,
           tracks.allSatisfy({ $0.region == region && $0.recordingDay == day })
        { return .agreement(devices) }

        let knownDays = Set(tracks.compactMap(\.recordingDay))
        let divergent = tracks.enumerated().contains { index, left in
            tracks.dropFirst(index + 1).contains { right in
                hasRepeatedBrackets(left) && hasRepeatedBrackets(right)
                    && left.bracketingObservations.allSatisfy { leftObservation in
                        right.bracketingObservations.allSatisfy { rightObservation in
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

    private static func hasRepeatedBrackets(_ track: Track) -> Bool {
        guard let first = track.bracketingObservations.first,
              let last = track.bracketingObservations.last,
              last.sample.timestamp.timeIntervalSince(first.sample.timestamp)
              >= RecordingEvidencePolicy.minimumAnchorInterval
        else { return false }
        return track.bracketingObservations.allSatisfy {
            $0.sample.horizontalAccuracy <= RecordingEvidencePolicy.maximumAccuracyMeters
        }
    }
}
