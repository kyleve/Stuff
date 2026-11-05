import Foundation

/// Resolves durable source and eligibility controls before automatic assessment. Explicit
/// sources bypass ignores, but never removal cutoffs or controls whose meaning is unknown.
public enum RecordingControlSelection {
    public enum Eligibility: Hashable, Sendable {
        case eligible
        case ignored
        case removed
        case conflict(Set<RecordingIgnoreDecision.ID>)
        case incomplete(Set<RecordingIgnoreDecision.ID>)
    }

    public struct Automatic: Hashable, Sendable {
        public let devices: [RecordingDeviceID: Eligibility]

        public func eligibility(of deviceID: RecordingDeviceID) -> Eligibility {
            devices[deviceID] ?? .eligible
        }
    }

    public enum Problem: Hashable, Sendable {
        case sourceConflict(Set<HistoryDecision.ID>)
        case missingSourceChoices(Set<HistoryDecision.ID>)
        case selectedDeviceRemoved(RecordingDeviceID)
        case unknownControls(Set<VersionedHistoryRecord.ID>)
    }

    public enum Resolution: Hashable, Sendable {
        case automatic(Automatic)
        case selected(RecordingDeviceID)
        case unresolved(Problem)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let resolution: Resolution
        public let sourceChoiceIDs: Set<HistoryDecision.ID>
    }

    public enum ValidationError: Error {
        case invalidRemoval(RecordingDeviceRemoval.ID)
        case conflictingRemoval(RecordingDeviceRemoval.ID)
    }

    public static func resolve(
        controls: RecordingControlSnapshot,
        removals: [RecordingDeviceRemoval],
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        let sources = try HistoryDecisionResolver.resolve(
            controls.sourceChoices,
            within: query,
            version: version,
        )
        let deviceIDs = Set(controls.ignores.map(\.deviceID))
        var ignores: [RecordingDeviceID: [RecordingIgnoreResolver.Segment]] = [:]
        for deviceID in deviceIDs {
            ignores[deviceID] = try RecordingIgnoreResolver.resolve(
                controls.ignores,
                for: deviceID,
                within: query,
                version: version,
            )
        }
        let cutoffs = try removalCutoffs(removals)
        let opaquePeriods = controls.requiresReview.flatMap { record -> [RecordingPeriod] in
            record.scope.intersections(with: query)
        }
        let boundaries = Set(
            [query.start, query.end]
                + sources.flatMap { [$0.period.start, $0.period.end] }
                + ignores.values.flatMap { $0.flatMap { [$0.period.start, $0.period.end] } }
                + opaquePeriods.flatMap { [$0.start, $0.end] }
                + cutoffs.values.filter { query.contains($0) },
        ).sorted()
        return try zip(boundaries, boundaries.dropFirst()).map { start, end in
            let period = try RecordingPeriod(start: start, end: end)
            // The source resolver covers the entire query, including periods with no choices.
            guard let source = sources.first(where: { $0.period.contains(start) }) else {
                preconditionFailure("Source resolution must cover the requested period.")
            }
            let opaque = Set(controls.requiresReview.filter { record in
                record.scope.contains(start)
            }.map(\.id))
            let resolution: Resolution
            if !opaque.isEmpty {
                resolution = .unresolved(.unknownControls(opaque))
            } else {
                switch source.resolution {
                    case let .conflict(identities):
                        resolution = .unresolved(.sourceConflict(identities))
                    case let .incomplete(identities):
                        resolution = .unresolved(.missingSourceChoices(identities))
                    case let .selected(deviceID):
                        if let cutoff = cutoffs[deviceID], cutoff <= start {
                            resolution = .unresolved(.selectedDeviceRemoved(deviceID))
                        } else {
                            resolution = .selected(deviceID)
                        }
                    case .automatic:
                        var devices: [RecordingDeviceID: Eligibility] = [:]
                        for (deviceID, segments) in ignores {
                            if let segment = segments.first(where: { $0.period.contains(start) }) {
                                devices[deviceID] = switch segment.resolution {
                                    case .eligible: .eligible
                                    case .ignored: .ignored
                                    case let .conflict(identities): .conflict(identities)
                                    case let .incomplete(identities): .incomplete(identities)
                                }
                            }
                        }
                        for (deviceID, cutoff) in cutoffs where cutoff <= start {
                            devices[deviceID] = .removed
                        }
                        resolution = .automatic(Automatic(devices: devices))
                }
            }
            return Segment(
                period: period,
                resolution: resolution,
                sourceChoiceIDs: source.effectiveDecisions,
            )
        }
    }

    private static func removalCutoffs(_ removals: [RecordingDeviceRemoval]) throws
        -> [RecordingDeviceID: Date]
    {
        var records: [RecordingDeviceRemoval.ID: RecordingDeviceRemoval] = [:]
        var cutoffs: [RecordingDeviceID: Date] = [:]
        for removal in removals {
            guard removal.removedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw ValidationError.invalidRemoval(removal.id)
            }
            if let existing = records[removal.id], existing != removal {
                throw ValidationError.conflictingRemoval(removal.id)
            }
            records[removal.id] = removal
            cutoffs[removal.deviceID] = min(
                cutoffs[removal.deviceID] ?? removal.removedAt,
                removal.removedAt,
            )
        }
        return cutoffs
    }
}
